import { type ExtensionAPI, type ExtensionContext, type Theme } from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth, type TUI } from "@mariozechner/pi-tui";

const FOOTER_PADDING_X = 1;

function padded(line: string, width: number): string {
	if (width <= 0) return "";
	const padding = " ".repeat(Math.min(FOOTER_PADDING_X, Math.floor(width / 2)));
	const innerWidth = Math.max(0, width - visibleWidth(padding) * 2);
	const inner = truncateToWidth(line, innerWidth, "");
	const fill = " ".repeat(Math.max(0, innerWidth - visibleWidth(inner)));
	return truncateToWidth(`${padding}${inner}${fill}${padding}`, width, "");
}

function clamp(value: number, min: number, max: number): number {
	return Math.max(min, Math.min(max, value));
}

function contextColor(theme: Theme, percent: number, text: string): string {
	if (percent >= 90) return theme.fg("error", text);
	if (percent >= 75) return theme.fg("warning", text);
	if (percent >= 50) return theme.fg("accent", text);
	return theme.fg("success", text);
}

function formatContextBar(ctx: ExtensionContext, theme: Theme, barWidth: number): string {
	const usage = ctx.getContextUsage();
	if (!usage || usage.percent === null) {
		return `${theme.fg("dim", "ctx")} ${theme.fg("borderMuted", "[")}${theme.fg("borderMuted", "░".repeat(barWidth))}${theme.fg("borderMuted", "]")} ${theme.fg("dim", "?")}`;
	}

	const percent = clamp(Math.round(usage.percent), 0, 100);
	const filled = clamp(Math.round((percent / 100) * barWidth), 0, barWidth);
	const empty = barWidth - filled;
	const filledBar = contextColor(theme, percent, "█".repeat(filled));
	const emptyBar = theme.fg("borderMuted", "░".repeat(empty));
	const pct = contextColor(theme, percent, `${percent}%`);

	return `${theme.fg("dim", "ctx")} ${theme.fg("borderMuted", "[")}${filledBar}${emptyBar}${theme.fg("borderMuted", "]")} ${pct}`;
}

function styleThinking(theme: Theme, level: string): string {
	switch (level) {
		case "off":
			return theme.fg("thinkingOff", level);
		case "minimal":
			return theme.fg("thinkingMinimal", level);
		case "low":
			return theme.fg("thinkingLow", level);
		case "medium":
			return theme.fg("thinkingMedium", level);
		case "high":
			return theme.fg("thinkingHigh", level);
		case "xhigh":
			return theme.fg("thinkingXhigh", level);
		default:
			return theme.fg("muted", level);
	}
}

export default function (pi: ExtensionAPI) {
	let activeTui: TUI | undefined;

	pi.on("model_select", () => activeTui?.requestRender());
	pi.on("thinking_level_select", () => activeTui?.requestRender());
	pi.on("agent_end", () => activeTui?.requestRender());
	pi.on("session_shutdown", () => {
		activeTui = undefined;
	});

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;

		ctx.ui.setFooter((tui, theme, footerData) => {
			activeTui = tui;
			const unsub = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose: unsub,
				invalidate() {},
				render(width: number): string[] {
					const innerWidth = Math.max(0, width - FOOTER_PADDING_X * 2);
					const model = theme.fg("accent", ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "no model");
					const thinking = styleThinking(theme, pi.getThinkingLevel());
					const separator = theme.fg("dim", "·");
					const rightSideWidth = visibleWidth(`${separator} ${model} ${separator} ${thinking}`);
					const barWidth = clamp(innerWidth - rightSideWidth - 13, 6, 18);
					const context = formatContextBar(ctx, theme, barWidth);
					const line = `${context} ${separator} ${model} ${separator} ${thinking}`;
					return [padded(truncateToWidth(line, innerWidth, ""), width)];
				},
			};
		});
	});

	pi.registerCommand("footer-ui", {
		description: "Restore Pi's built-in footer for this session.",
		handler: async (_args, ctx) => {
			ctx.ui.setFooter(undefined);
			ctx.ui.notify("Built-in footer restored for this session", "info");
		},
	});
}
