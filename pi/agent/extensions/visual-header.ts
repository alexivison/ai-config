import path from "node:path";
import { VERSION, type ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@mariozechner/pi-tui";

function shortPath(cwd: string): string {
	const home = process.env.HOME;
	if (home && cwd.startsWith(home)) return `~${cwd.slice(home.length)}`;
	return cwd;
}

function row(left: string, right: string, width: number): string {
	if (width <= 0) return "";
	const gap = Math.max(1, width - visibleWidth(left) - visibleWidth(right));
	return truncateToWidth(`${left}${" ".repeat(gap)}${right}`, width, "");
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;

		ctx.ui.setTitle(`π Pi — ${path.basename(ctx.cwd)}`);

		ctx.ui.setHeader((_tui, theme) => ({
			invalidate() {},
			render(width: number): string[] {
				const rule = theme.fg("borderMuted", "─".repeat(Math.max(0, width)));
				const title = `${theme.fg("accent", theme.bold("π Pi"))} ${theme.fg("muted", "terminal coding agent")}`;
				const version = theme.fg("dim", `v${VERSION}`);

				const model = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "no model";
				const thinking = pi.getThinkingLevel();
				const cwd = shortPath(ctx.cwd);

				const palette = [
					theme.fg("accent", "●"),
					theme.fg("success", "●"),
					theme.fg("warning", "●"),
					theme.fg("error", "●"),
					theme.fg("thinkingHigh", "●"),
					theme.fg("mdLink", "●"),
				].join(" ");

				const hints = [
					theme.fg("accent", "Ctrl+L"),
					theme.fg("dim", "model"),
					theme.fg("accent", "Shift+Tab"),
					theme.fg("dim", "thinking"),
					theme.fg("accent", "Ctrl+O"),
					theme.fg("dim", "tools"),
					theme.fg("accent", "/hotkeys"),
				].join(" ");

				if (width < 56) {
					return [
						rule,
						row(title, version, width),
						truncateToWidth(theme.fg("dim", `${model} · ${thinking}`), width, ""),
						rule,
					];
				}

				return [
					rule,
					row(title, version, width),
					row(theme.fg("dim", cwd), theme.fg("muted", `${model} · ${thinking}`), width),
					row(palette, hints, width),
					rule,
				];
			},
		}));
	});

	pi.registerCommand("startup-ui", {
		description: "Restore Pi's built-in startup header for this session.",
		handler: async (_args, ctx) => {
			ctx.ui.setHeader(undefined);
			ctx.ui.notify("Built-in startup header restored for this session", "info");
		},
	});
}
