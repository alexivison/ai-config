import { spawnSync } from "node:child_process";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { Type } from "typebox";

const PARTY_CLI = "party-cli";
const PARTY_SESSION = process.env.PARTY_SESSION;
const HOOK_TIMEOUT_MS = 1_000;

const OptionSchema = Type.Object({
	id: Type.Optional(Type.String({ description: "Stable option identifier returned to the agent" })),
	label: Type.String({ description: "Display label for the option" }),
	description: Type.Optional(Type.String({ description: "Optional description shown with the option" })),
});

const AskUserParams = Type.Object({
	question: Type.String({ description: "Question to ask the user" }),
	options: Type.Array(OptionSchema, { description: "Options the user can choose from" }),
	allowOther: Type.Optional(Type.Boolean({ description: "Allow the user to type a custom response" })),
});

type AskUserOption = {
	id?: string;
	label: string;
	description?: string;
};

type SessionManagerLike = {
	getSessionId?: () => string | undefined;
	getSessionFile?: () => string | undefined;
};

type AskUserSelection = AskUserOption & {
	other?: boolean;
};

type AskUserDetails = {
	question: string;
	options: AskUserOption[];
	selected: AskUserSelection | null;
	cancelled: boolean;
};

function choiceLabel(option: AskUserOption, index: number): string {
	const prefix = option.id ? `${option.id}: ` : `${index + 1}. `;
	const description = option.description ? ` — ${option.description}` : "";
	return `${prefix}${option.label}${description}`;
}

function hookPayload(ctx: { cwd?: string; sessionManager?: unknown }, question: string, options: AskUserOption[]) {
	const sessionManager = ctx.sessionManager as SessionManagerLike | undefined;
	const piSessionID = sessionManager?.getSessionId?.();
	const sessionFile = sessionManager?.getSessionFile?.();

	return {
		version: 1,
		source: "pi",
		...(PARTY_SESSION ? { id: PARTY_SESSION, session_id: PARTY_SESSION } : {}),
		...(piSessionID ? { pi_session_id: piSessionID } : {}),
		...(sessionFile ? { session_file: sessionFile } : {}),
		...(ctx.cwd ? { cwd: ctx.cwd } : {}),
		updated_at_ms: Date.now(),
		prompt: question,
		tool: { name: "ask_user", summary: question },
		options,
	};
}

function emitHook(action: "waiting_for_user" | "tool_execution_end", payload: Record<string, unknown>) {
	if (!PARTY_SESSION) return;
	try {
		spawnSync(PARTY_CLI, ["hook", "pi", action], {
			input: `${JSON.stringify(payload)}\n`,
			stdio: ["pipe", "ignore", "ignore"],
			timeout: HOOK_TIMEOUT_MS,
		});
	} catch {
		// Hook delivery is best-effort only; never disturb Pi.
	}
}

function errorResult(message: string, question: string, options: AskUserOption[] = []) {
	return {
		content: [{ type: "text" as const, text: message }],
		details: { question, options, selected: null, cancelled: true } as AskUserDetails,
	};
}

function selectionResult(question: string, options: AskUserOption[], selected: AskUserSelection) {
	const idPart = selected.id ? ` (${selected.id})` : "";
	return {
		content: [{ type: "text" as const, text: `User selected${idPart}: ${selected.label}` }],
		details: { question, options, selected, cancelled: false } as AskUserDetails,
	};
}

export default function askUser(pi: ExtensionAPI) {
	pi.registerTool({
		name: "ask_user",
		label: "Ask User",
		description: "Ask the user a blocking question and return the selected option. Use when user input is required to proceed.",
		parameters: AskUserParams,

		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			if (!ctx.hasUI) {
				return errorResult("Error: UI not available (running in non-interactive mode)", params.question, params.options);
			}

			if (params.options.length === 0 && !params.allowOther) {
				return errorResult("Error: No options provided", params.question, params.options);
			}

			const choices = new Map<string, AskUserOption>();
			const labels = params.options.map((option: AskUserOption, index: number) => {
				const label = choiceLabel(option, index);
				choices.set(label, option);
				return label;
			});
			const otherLabel = "Other…";
			if (params.allowOther) labels.push(otherLabel);

			const payload = hookPayload(ctx, params.question, params.options);
			emitHook("waiting_for_user", payload);

			try {
				const selectedLabel = labels.length === 1 && params.allowOther ? otherLabel : await ctx.ui.select(params.question, labels);
				if (!selectedLabel) {
					return errorResult("User cancelled the selection", params.question, params.options);
				}

				if (selectedLabel === otherLabel) {
					const custom = (await ctx.ui.input(params.question, "Type your response"))?.trim();
					if (!custom) {
						return errorResult("User cancelled the selection", params.question, params.options);
					}
					return selectionResult(params.question, params.options, { label: custom, other: true });
				}

				const selected = choices.get(selectedLabel);
				if (!selected) {
					return errorResult("User cancelled the selection", params.question, params.options);
				}
				return selectionResult(params.question, params.options, selected);
			} finally {
				emitHook("tool_execution_end", payload);
			}
		},
	});
}
