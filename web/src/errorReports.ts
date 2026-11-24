/**
 * Returns a filter that passes each distinct error message once.
 * It drops "ResizeObserver loop" messages, because the browser reports them
 * for layout that settles in the next frame.
 */
export function errorFilter(): (message: string) => boolean {
	const seen = new Set<string>();
	return (message) => {
		if (message.includes("ResizeObserver loop") || seen.has(message)) return false;
		seen.add(message);
		return true;
	};
}
