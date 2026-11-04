/** The last text of the open file, for `window.piper.flush`. */
let latest: { path: string; text: string } | null = null;

export function noteLocalChange(path: string, text: string) {
	latest = { path, text };
}

export function resetLatest(path: string, text: string) {
	latest = { path, text };
}

export function latestText(path: string): string | null {
	return latest?.path === path ? latest.text : null;
}
