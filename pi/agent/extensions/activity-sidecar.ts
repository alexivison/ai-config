import { mkdirSync, renameSync, writeFileSync } from "node:fs";
import path from "node:path";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

const ACTIVITY_FILE = process.env.PI_ACTIVITY_FILE;
const ACTIVITY_ID = process.env.PI_ACTIVITY_ID;
const RECENT_LIMIT = 40;
const SNIPPET_LIMIT = 180;
const HEARTBEAT_MS = 1_500;
const WRITE_THROTTLE_MS = 100;

type ActivityPhase = "idle" | "thinking" | "message_update" | "tool" | "done" | "error";

type ActivityState = {
	version: 1;
	source: "pi";
	id?: string;
	session_id?: string;
	session_file?: string;
	cwd?: string;
	updated_at_ms: number;
	busy: boolean;
	phase: ActivityPhase;
	snippet?: string;
	recent?: string[];
};

type TextContent = { type?: string; text?: unknown; thinking?: unknown };
type AgentMessage = { role?: string; content?: unknown };
type SessionManagerLike = { getSessionId?: () => string | undefined; getSessionFile?: () => string | undefined };

type ToolEvent = {
	toolName?: string;
	args?: unknown;
	input?: unknown;
	result?: { content?: unknown };
	partialResult?: { content?: unknown };
	isError?: boolean;
};

function safeLine(text: string, limit = SNIPPET_LIMIT): string {
	return text.replace(/\s+/g, " ").trim().slice(0, limit);
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

function contentText(content: unknown): string {
	return textFromContent(content);
}

function toolArgs(args: unknown): Record<string, unknown> {
	return args && typeof args === "object" ? (args as Record<string, unknown>) : {};
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

export default function (pi: ExtensionAPI) {
	if (!ACTIVITY_FILE) return;

	const activityPath = path.resolve(ACTIVITY_FILE);
	let busy = false;
	let phase: ActivityPhase = "idle";
	let snippet = "";
	let recent: string[] = [];
	let heartbeat: NodeJS.Timeout | undefined;
	let pendingWrite: NodeJS.Timeout | undefined;
	let currentTool = "";
	let sessionID = ACTIVITY_ID || "";
	let sessionFile = "";
	let cwd = process.cwd();

	function pushRecent(line: string | undefined) {
		const clean = safeLine(line ?? "");
		if (!clean || recent[recent.length - 1] === clean) return;
		recent.push(clean);
		if (recent.length > RECENT_LIMIT) recent = recent.slice(recent.length - RECENT_LIMIT);
	}

	function setSnippet(next: string | undefined, nextPhase?: ActivityPhase) {
		const clean = safeLine(next ?? "");
		if (nextPhase) phase = nextPhase;
		if (clean) {
			snippet = clean;
			pushRecent(clean);
		}
		scheduleWrite();
	}

	function writeState() {
		pendingWrite = undefined;
		try {
			mkdirSync(path.dirname(activityPath), { recursive: true });
			const state: ActivityState = {
				version: 1,
				source: "pi",
				...(sessionID ? { id: sessionID, session_id: sessionID } : {}),
				...(sessionFile ? { session_file: sessionFile } : {}),
				...(cwd ? { cwd } : {}),
				updated_at_ms: Date.now(),
				busy,
				phase,
				...(snippet ? { snippet } : {}),
				...(recent.length > 0 ? { recent } : {}),
			};
			const tmp = `${activityPath}.${process.pid}.tmp`;
			writeFileSync(tmp, `${JSON.stringify(state)}\n`, "utf8");
			renameSync(tmp, activityPath);
		} catch {
			// Activity sidecar is best-effort only; never disturb Pi.
		}
	}

	function scheduleWrite() {
		if (pendingWrite) return;
		pendingWrite = setTimeout(writeState, WRITE_THROTTLE_MS);
	}

	function startHeartbeat() {
		if (heartbeat) return;
		heartbeat = setInterval(writeState, HEARTBEAT_MS);
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
		writeState();
	}

	pi.on("session_start", (_event, ctx) => {
		const sessionManager = ctx.sessionManager as SessionManagerLike;
		sessionID = ACTIVITY_ID || sessionManager.getSessionId?.() || sessionID;
		sessionFile = sessionManager.getSessionFile?.() || sessionFile;
		cwd = ctx.cwd || cwd;
		setBusy(false, "idle");
	});

	pi.on("agent_start", () => {
		currentTool = "";
		setBusy(true, "thinking", "Thinking...");
	});

	pi.on("message_update", (event: { message?: unknown; assistantMessageEvent?: { type?: string; delta?: unknown; content?: unknown } }) => {
		const delta = event.assistantMessageEvent;
		if (delta?.type === "thinking_delta" || thinkingFromContent((event.message as AgentMessage | undefined)?.content)) {
			if (!snippet || snippet === "Thinking...") setSnippet("Thinking...", "thinking");
			return;
		}

		if (delta?.type === "text_delta" && typeof delta.delta === "string") {
			setSnippet(lastTextLine(textFromMessage(event.message)) ?? lastTextLine(delta.delta), "message_update");
			return;
		}

		if (delta?.type === "text_end") {
			const text = typeof delta.content === "string" ? delta.content : textFromMessage(event.message);
			for (const line of nonEmptyLines(text).slice(-RECENT_LIMIT)) pushRecent(line);
			setSnippet(lastTextLine(text), "message_update");
		}
	});

	pi.on("message_end", (event: { message?: unknown }) => {
		const text = textFromMessage(event.message);
		if (!text) return;
		for (const line of nonEmptyLines(text).slice(-RECENT_LIMIT)) pushRecent(line);
		setSnippet(lastTextLine(text), "message_update");
	});

	pi.on("tool_execution_start", (event: ToolEvent) => {
		currentTool = formatTool(event.toolName, event.args ?? event.input);
		setSnippet(currentTool, "tool");
	});

	pi.on("tool_execution_update", (event: ToolEvent) => {
		const output = contentText(event.partialResult?.content);
		setSnippet(lastTextLine(output) ?? currentTool, "tool");
	});

	pi.on("tool_execution_end", (event: ToolEvent) => {
		const output = contentText(event.result?.content);
		const label = currentTool || formatTool(event.toolName, event.args ?? event.input);
		setSnippet(lastTextLine(output) ?? `${event.isError ? "✗" : "✓"} ${label}`, event.isError ? "error" : "tool");
		currentTool = "";
	});

	pi.on("agent_end", (event: { messages?: unknown[] }) => {
		for (const message of event.messages ?? []) {
			const text = textFromMessage(message);
			if (!text) continue;
			for (const line of nonEmptyLines(text).slice(-RECENT_LIMIT)) pushRecent(line);
			snippet = lastTextLine(text) ?? snippet;
		}
		setBusy(false, "done", snippet || "Done");
	});

	pi.on("session_shutdown", () => {
		stopHeartbeat();
		if (pendingWrite) {
			clearTimeout(pendingWrite);
			pendingWrite = undefined;
		}
		setBusy(false, "idle", snippet);
	});
}
