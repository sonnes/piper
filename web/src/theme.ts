import type { Theme } from "./bridge";

const dark = window.matchMedia("(prefers-color-scheme: dark)");
let current: Theme | null = null;

export function applyTheme(theme: Theme) {
	current = theme;
	const root = document.documentElement;
	root.dataset.theme = theme.theme.toLowerCase();
	root.dataset.font = theme.font === "Sans Serif" ? "sans" : theme.font === "Monospace" ? "mono" : "serif";
	root.style.setProperty("--font-size-content", `${theme.size}px`);
	const isDark = theme.appearance === "Dark" || (theme.appearance === "System" && dark.matches);
	root.classList.toggle("dark", isDark);
}

dark.addEventListener("change", () => {
	if (current) applyTheme(current);
});
