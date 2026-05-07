import {
	createReadToolDefinition,
	type ExtensionAPI,
	type ReadToolInput,
	type Theme,
} from "@mariozechner/pi-coding-agent";
import { Text } from "@mariozechner/pi-tui";

function shortPath(filePath: string): string {
	const home = process.env.HOME;
	if (home && filePath.startsWith(home)) return `~${filePath.slice(home.length)}`;
	return filePath;
}

function lineRange(args: ReadToolInput): string {
	if (args.offset === undefined && args.limit === undefined) return "";
	const start = args.offset ?? 1;
	const end = args.limit === undefined ? "" : start + args.limit - 1;
	return `:${start}${end ? `-${end}` : ""}`;
}

function readLabel(args: ReadToolInput, theme: Theme): string {
	const filePath = shortPath(args.path || "...");
	return `${theme.fg("toolTitle", theme.bold("Read"))} ${theme.fg("accent", filePath)}${theme.fg("warning", lineRange(args))}`;
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.hasUI) ctx.ui.setToolsExpanded(false);

		const readTool = createReadToolDefinition(ctx.cwd);
		pi.registerTool({
			...readTool,
			renderCall(args, theme, context) {
				const text = context.lastComponent ?? new Text("", 0, 0);
				text.setText(readLabel(args, theme));
				return text;
			},
			renderResult(result, _options, theme, context) {
				const text = context.lastComponent ?? new Text("", 0, 0);
				if (context.isError) {
					const message = result.content.find((item) => item.type === "text")?.text ?? "Read failed";
					text.setText(`\n${theme.fg("error", message.split("\n")[0])}`);
				} else {
					text.setText("");
				}
				return text;
			},
		});
	});

	pi.registerCommand("tools-compact", {
		description: "Collapse tool output and keep read results hidden.",
		handler: async (_args, ctx) => {
			ctx.ui.setToolsExpanded(false);
			ctx.ui.notify("Tool output collapsed", "info");
		},
	});

	pi.registerCommand("tools-expanded", {
		description: "Expand tool output for this session; read file contents stay hidden.",
		handler: async (_args, ctx) => {
			ctx.ui.setToolsExpanded(true);
			ctx.ui.notify("Tool output expanded", "info");
		},
	});
}
