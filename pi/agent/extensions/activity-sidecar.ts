import { mkdirSync, writeFileSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import type { ExtensionAPI, ExtensionContext } from "@mariozechner/pi-coding-agent";

const PARTY_CLI = "party-cli";
const PARTY_SESSION = process.env.PARTY_SESSION;
const SIDECAR_VERSION = "phase2-v1";
const RECENT_LIMIT = 40;
const SNIPPET_LIMIT = 180;
const HEARTBEAT_MS = 1_500;

type PiHookAction =
	| "session_start"
	| "before_agent_start"
	| "agent_start"
	| "message_update"
	| "message_end"
	| "tool_execution_start"
	| "tool_execution_end"
	| "agent_end"
	| "session_shutdown";

type ActivityPhase = "idle" | "thinking" | "message_update" | "tool" | "done" | "error";

type ActivityModel = {
	provider?: string;
	id?: string;
	name?: string;
	api?: string;
	reasoning?: boolean;
	context_window?: number;
	max_tokens?: number;
	input?: string[];
};

type ActivityThinking = {
	level?: string;
};

type ActivityContext = {
	tokens?: number | null;
	context_window?: number;
	percent?: number | null;
};

type ActivityTurn = {
	index?: number;
	status?: "running" | "done";
	started_at_ms?: number;
	ended_at_ms?: number;
	tool_calls?: number;
	errors?: number;
};

type ActivityTool = {
	name?: string;
	call_id?: string;
	summary?: string;
	status?: "running" | "done" | "error";
	started_at_ms?: number;
	ended_at_ms?: number;
};

type ActivityUsageSnapshot = {
	input?: number;
	output?: number;
	cache_read?: number;
	cache_write?: number;
	total_tokens?: number;
	cost_total?: number;
};

type ActivityUsage = {
	last?: ActivityUsageSnapshot;
};

type ActivityState = {
	version: 1;
	source: "pi";
	id?: string;
	session_id?: string;
	pi_session_id?: string;
	session_file?: string;
	cwd?: string;
	updated_at_ms: number;
	busy: boolean;
	phase: ActivityPhase;
	snippet?: string;
	recent?: string[];
	model?: ActivityModel;
	thinking?: ActivityThinking;
	context?: ActivityContext;
	turn?: ActivityTurn;
	tool?: ActivityTool;
	usage?: ActivityUsage;
};

type TextContent = { type?: string; text?: unknown; thinking?: unknown };
type AgentMessage = { role?: string; content?: unknown };
type SessionManagerLike = { getSessionId?: () => string | undefined; getSessionFile?: () => string | undefined };

type ToolEvent = {
	toolCallId?: string;
	toolName?: string;
	name?: string;
	args?: unknown;
	arguments?: unknown;
	input?: unknown;
	result?: { content?: unknown };
	partialResult?: { content?: unknown };
	isError?: boolean;
};

function safeLine(text: string, limit = SNIPPET_LIMIT): string {
	return text.replace(/\s+/g, " ").trim().slice(0, limit);
}

function cleanString(value: unknown, limit = SNIPPET_LIMIT): string | undefined {
	return typeof value === "string" && value.trim() ? safeLine(value, limit) : undefined;
}

function cleanNumber(value: unknown): number | undefined {
	return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function cleanNullableNumber(value: unknown): number | null | undefined {
	return value === null ? null : cleanNumber(value);
}

function nonEmptyLines(text: string): string[] {
	return text
		.split("\n")
		.map((line) => line.trim())
		.filter(Boolean);
}

function lastTextLine(text: string): string | undefined {
	const lines = nonEmptyLines(text);
	return lines.length > 0 ? safeLine(lines[lines.length - 1]) : undefined;
}

function textFromContent(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	return content
		.map((item: TextContent) => {
			if (item?.type === "text" && typeof item.text === "string") return item.text;
			return "";
		})
		.filter(Boolean)
		.join("\n");
}

function thinkingFromContent(content: unknown): string {
	if (!Array.isArray(content)) return "";
	return content
		.map((item: TextContent) => {
			if (item?.type === "thinking" && typeof item.thinking === "string") return item.thinking;
			return "";
		})
		.filter(Boolean)
		.join("\n");
}

function textFromMessage(message: unknown): string {
	const msg = message as AgentMessage | undefined;
	if (!msg || msg.role !== "assistant") return "";
	return textFromContent(msg.content);
}

function toolArgs(args: unknown): Record<string, unknown> {
	if (args && typeof args === "object") return args as Record<string, unknown>;
	if (typeof args !== "string" || !args.trim()) return {};
	try {
		const parsed = JSON.parse(args) as unknown;
		return parsed && typeof parsed === "object" ? (parsed as Record<string, unknown>) : {};
	} catch {
		return {};
	}
}

function argString(args: Record<string, unknown>, keys: string[]): string | undefined {
	for (const key of keys) {
		const value = args[key];
		if (typeof value === "string" && value.trim()) return safeLine(value, 120);
	}
	return undefined;
}

function formatTool(toolName: string | undefined, rawArgs: unknown): string {
	const name = toolName || "tool";
	const args = toolArgs(rawArgs);
	switch (name) {
		case "bash":
			return `bash: ${argString(args, ["command"]) ?? "running"}`;
		case "read":
			return `read: ${argString(args, ["path"]) ?? "file"}`;
		case "edit":
		case "write":
			return `${name}: ${argString(args, ["path"]) ?? "file"}`;
		case "grep":
			return `grep: ${argString(args, ["pattern", "query"]) ?? "search"}`;
		case "find":
			return `find: ${argString(args, ["pattern", "path"]) ?? "files"}`;
		case "ls":
			return `ls: ${argString(args, ["path"]) ?? "directory"}`;
		default:
			return name;
	}
}

function modelState(raw: unknown): ActivityModel | undefined {
	if (!raw || typeof raw !== "object") return undefined;
	const model = raw as Record<string, unknown>;
	const input = Array.isArray(model.input) ? model.input.filter((value): value is string => typeof value === "string") : undefined;
	const state: ActivityModel = {
		provider: cleanString(model.provider, 80),
		id: cleanString(model.id, 120),
		name: cleanString(model.name, 120),
		api: cleanString(model.api, 80),
		...(typeof model.reasoning === "boolean" ? { reasoning: model.reasoning } : {}),
		context_window: cleanNumber(model.contextWindow),
		max_tokens: cleanNumber(model.maxTokens),
		...(input && input.length > 0 ? { input } : {}),
	};
	return Object.values(state).some((value) => value !== undefined) ? state : undefined;
}

function mergeAssistantModel(current: ActivityModel | undefined, message: unknown): ActivityModel | undefined {
	if (!message || typeof message !== "object" || (message as AgentMessage).role !== "assistant") return current;
	const msg = message as Record<string, unknown>;
	const next = { ...(current ?? {}) };
	next.provider = cleanString(msg.provider, 80) ?? next.provider;
	next.id = cleanString(msg.model, 120) ?? next.id;
	next.api = cleanString(msg.api, 80) ?? next.api;
	return Object.values(next).some((value) => value !== undefined) ? next : undefined;
}

function contextState(ctx: ExtensionContext): ActivityContext | undefined {
	const usage = ctx.getContextUsage?.();
	if (!usage) return undefined;
	const state: ActivityContext = {
		tokens: cleanNullableNumber(usage.tokens),
		context_window: cleanNumber(usage.contextWindow),
		percent: cleanNullableNumber(usage.percent),
	};
	return Object.values(state).some((value) => value !== undefined) ? state : undefined;
}

function usageSnapshot(raw: unknown): ActivityUsageSnapshot | undefined {
	if (!raw || typeof raw !== "object") return undefined;
	const usage = raw as Record<string, unknown>;
	const cost = usage.cost && typeof usage.cost === "object" ? (usage.cost as Record<string, unknown>) : {};
	const state: ActivityUsageSnapshot = {
		input: cleanNumber(usage.input),
		output: cleanNumber(usage.output),
		cache_read: cleanNumber(usage.cacheRead),
		cache_write: cleanNumber(usage.cacheWrite),
		total_tokens: cleanNumber(usage.totalTokens),
		cost_total: cleanNumber(cost.total),
	};
	return Object.values(state).some((value) => value !== undefined) ? state : undefined;
}

function assistantUsage(message: unknown): ActivityUsageSnapshot | undefined {
	if (!message || typeof message !== "object" || (message as AgentMessage).role !== "assistant") return undefined;
	return usageSnapshot((message as Record<string, unknown>).usage);
}

function validPartySession(value: string | undefined): value is string {
	return typeof value === "string" && /^party-[A-Za-z0-9_-]+$/.test(value);
}

function markerPaths(): string[] {
	const piHome = process.env.PI_HOME || (process.env.HOME ? path.join(process.env.HOME, ".pi") : "");
	if (!piHome) return [];
	return [
		path.join(piHome, "agent", "extensions", ".party-cli-installed"),
		path.join(piHome, "extensions", ".party-cli-installed"),
	];
}

function writeSidecarMarker() {
	for (const markerPath of markerPaths()) {
		try {
			mkdirSync(path.dirname(markerPath), { recursive: true });
			writeFileSync(markerPath, `${SIDECAR_VERSION}\n`, "utf8");
		} catch {
			// Marker writes are best-effort only; never disturb Pi.
		}
	}
}

function promptFromBeforeAgentStart(event: unknown): string | undefined {
	if (!event || typeof event !== "object") return undefined;
	const record = event as Record<string, unknown>;
	for (const key of ["prompt", "input", "message"]) {
		const value = cleanString(record[key]);
		if (value) return value;
	}
	return undefined;
}

export default function (pi: ExtensionAPI) {
	let busy = false;
	let phase: ActivityPhase = "idle";
	let snippet = "";
	let recent: string[] = [];
	let heartbeat: NodeJS.Timeout | undefined;
	let currentTool = "";
	let partySessionID = validPartySession(PARTY_SESSION) ? PARTY_SESSION : "";
	let piSessionID = "";
	let sessionFile = "";
	let cwd = process.cwd();
	let model: ActivityModel | undefined;
	let thinking: ActivityThinking | undefined;
	let contextUsage: ActivityContext | undefined;
	let turn: ActivityTurn | undefined;
	let tool: ActivityTool | undefined;
	let usage: ActivityUsage | undefined;
	let lastAction: PiHookAction | undefined;

	function refreshModel(ctx: ExtensionContext) {
		model = modelState(ctx.model) ?? model;
	}

	function refreshThinking() {
		try {
			thinking = { level: safeLine(pi.getThinkingLevel(), 40) };
		} catch {
			// Thinking level may be unavailable before Pi finishes binding context.
		}
	}

	function refreshContext(ctx: ExtensionContext) {
		contextUsage = contextState(ctx) ?? contextUsage;
	}

	function recordAssistantMessage(message: unknown) {
		model = mergeAssistantModel(model, message);
		const last = assistantUsage(message);
		if (last) usage = { last };
	}

	function refreshMetadata(ctx: ExtensionContext) {
		refreshModel(ctx);
		refreshThinking();
		refreshContext(ctx);
	}

	function pushRecent(line: string | undefined) {
		const clean = safeLine(line ?? "");
		if (!clean || recent[recent.length - 1] === clean) return;
		recent.push(clean);
		if (recent.length > RECENT_LIMIT) recent = recent.slice(recent.length - RECENT_LIMIT);
	}

	function setSnippet(next: string | undefined, nextPhase?: ActivityPhase, remember = true) {
		const clean = safeLine(next ?? "");
		if (nextPhase) phase = nextPhase;
		if (clean) {
			snippet = clean;
			if (remember) pushRecent(clean);
		}
	}

	function activityPayload(extra?: Record<string, unknown>): ActivityState & Record<string, unknown> {
		return {
			version: 1,
			source: "pi",
			...(partySessionID ? { id: partySessionID, session_id: partySessionID } : {}),
			...(piSessionID ? { pi_session_id: piSessionID } : {}),
			...(sessionFile ? { session_file: sessionFile } : {}),
			...(cwd ? { cwd } : {}),
			updated_at_ms: Date.now(),
			busy,
			phase,
			...(snippet ? { snippet } : {}),
			...(recent.length > 0 ? { recent } : {}),
			...(model ? { model } : {}),
			...(thinking ? { thinking } : {}),
			...(contextUsage ? { context: contextUsage } : {}),
			...(turn ? { turn } : {}),
			...(tool ? { tool } : {}),
			...(usage ? { usage } : {}),
			...(extra ?? {}),
		};
	}

	function emitHook(action: PiHookAction, extra?: Record<string, unknown>) {
		lastAction = action;
		if (!partySessionID) return;
		try {
			spawnSync(PARTY_CLI, ["hook", "pi", action], {
				input: `${JSON.stringify(activityPayload(extra))}\n`,
				stdio: ["pipe", "ignore", "ignore"],
				timeout: 1_000,
			});
		} catch {
			// Hook delivery is best-effort only; never disturb Pi.
		}
	}

	function startHeartbeat() {
		if (heartbeat) return;
		heartbeat = setInterval(() => {
			if (lastAction) emitHook(lastAction);
		}, HEARTBEAT_MS);
	}

	function stopHeartbeat() {
		if (!heartbeat) return;
		clearInterval(heartbeat);
		heartbeat = undefined;
	}

	function setBusy(next: boolean, nextPhase: ActivityPhase, nextSnippet?: string) {
		busy = next;
		phase = nextPhase;
		if (nextSnippet) {
			snippet = safeLine(nextSnippet);
			pushRecent(snippet);
		}
		if (busy) startHeartbeat();
		else stopHeartbeat();
	}

	pi.on("session_start", (_event, ctx) => {
		const sessionManager = ctx.sessionManager as SessionManagerLike;
		piSessionID = sessionManager.getSessionId?.() || piSessionID;
		sessionFile = sessionManager.getSessionFile?.() || sessionFile;
		cwd = ctx.cwd || cwd;
		tool = undefined;
		refreshMetadata(ctx);
		setBusy(false, "idle");
		emitHook("session_start");
	});

	pi.on("before_agent_start", (event: unknown, ctx) => {
		writeSidecarMarker();
		cwd = ctx.cwd || cwd;
		refreshMetadata(ctx);
		const prompt = promptFromBeforeAgentStart(event);
		if (prompt) setSnippet(prompt, "thinking");
		emitHook("before_agent_start", prompt ? { prompt } : undefined);
	});

	pi.on("agent_start", (_event, ctx) => {
		currentTool = "";
		tool = undefined;
		refreshMetadata(ctx);
		setBusy(true, "thinking", "Thinking...");
		emitHook("agent_start");
	});

	pi.on("model_select", (event: { model?: unknown }) => {
		model = modelState(event.model) ?? model;
	});

	pi.on("thinking_level_select", (event: { level?: unknown }) => {
		const level = cleanString(event.level, 40);
		if (level) thinking = { level };
	});

	pi.on("context", (_event, ctx) => {
		refreshContext(ctx);
	});

	pi.on("turn_start", (event: { turnIndex?: unknown; timestamp?: unknown }, ctx) => {
		refreshMetadata(ctx);
		turn = {
			index: cleanNumber(event.turnIndex),
			status: "running",
			started_at_ms: cleanNumber(event.timestamp) ?? Date.now(),
		};
	});

	pi.on("turn_end", (event: { turnIndex?: unknown; message?: unknown; toolResults?: Array<{ isError?: boolean }> }, ctx) => {
		recordAssistantMessage(event.message);
		refreshMetadata(ctx);
		turn = {
			...(turn ?? {}),
			index: cleanNumber(event.turnIndex) ?? turn?.index,
			status: "done",
			ended_at_ms: Date.now(),
			tool_calls: Array.isArray(event.toolResults) ? event.toolResults.length : undefined,
			errors: Array.isArray(event.toolResults) ? event.toolResults.filter((result) => result?.isError).length : undefined,
		};
	});

	pi.on("message_update", (event: { message?: unknown; assistantMessageEvent?: { type?: string; delta?: unknown; content?: unknown } }) => {
		const delta = event.assistantMessageEvent;
		if (delta?.type === "thinking_delta" || thinkingFromContent((event.message as AgentMessage | undefined)?.content)) {
			if (!snippet || snippet === "Thinking...") setSnippet("Thinking...", "thinking");
		} else if (delta?.type === "text_delta" && typeof delta.delta === "string") {
			setSnippet(lastTextLine(textFromMessage(event.message)) ?? lastTextLine(delta.delta), "message_update", false);
		} else if (delta?.type === "text_end") {
			const text = typeof delta.content === "string" ? delta.content : textFromMessage(event.message);
			for (const line of nonEmptyLines(text).slice(-RECENT_LIMIT)) pushRecent(line);
			setSnippet(lastTextLine(text), "message_update");
		}
		emitHook("message_update");
	});

	pi.on("message_end", (event: { message?: unknown }) => {
		recordAssistantMessage(event.message);
		const text = textFromMessage(event.message);
		if (text) {
			for (const line of nonEmptyLines(text).slice(-RECENT_LIMIT)) pushRecent(line);
			setSnippet(lastTextLine(text), "message_update");
		}
		emitHook("message_end");
	});

	pi.on("tool_execution_start", (event: ToolEvent) => {
		const name = event.toolName ?? event.name;
		currentTool = formatTool(name, event.args ?? event.arguments ?? event.input);
		tool = {
			name: cleanString(name, 80) ?? "tool",
			call_id: cleanString(event.toolCallId, 120),
			summary: currentTool,
			status: "running",
			started_at_ms: Date.now(),
		};
		setSnippet(currentTool, "tool");
		emitHook("tool_execution_start");
	});

	pi.on("tool_execution_update", () => {
		if (tool) tool.status = "running";
		setSnippet(currentTool, "tool", false);
	});

	pi.on("tool_execution_end", (event: ToolEvent) => {
		const name = event.toolName ?? event.name;
		const label = currentTool || formatTool(name, event.args ?? event.arguments ?? event.input);
		tool = {
			...(tool ?? {}),
			name: cleanString(name, 80) ?? tool?.name ?? "tool",
			call_id: cleanString(event.toolCallId, 120) ?? tool?.call_id,
			summary: label,
			status: event.isError ? "error" : "done",
			ended_at_ms: Date.now(),
		};
		setSnippet(`${event.isError ? "✗" : "✓"} ${label}`, event.isError ? "error" : "tool");
		currentTool = "";
		emitHook("tool_execution_end");
	});

	pi.on("agent_end", (event: { messages?: unknown[] }, ctx) => {
		for (const message of event.messages ?? []) {
			recordAssistantMessage(message);
			const text = textFromMessage(message);
			if (!text) continue;
			for (const line of nonEmptyLines(text).slice(-RECENT_LIMIT)) pushRecent(line);
			snippet = lastTextLine(text) ?? snippet;
		}
		refreshMetadata(ctx);
		setBusy(false, "done", snippet || "Done");
		emitHook("agent_end");
	});

	pi.on("session_shutdown", () => {
		stopHeartbeat();
		setBusy(false, "idle", snippet);
		emitHook("session_shutdown");
	});
}
