export function normalizeDisplayPath(path: string) {
	return path.replace(/\\/g, "/").replace(/^\/+/, "");
}

export function fileNameFromPath(path: string) {
	const normalized = normalizeDisplayPath(path);
	const segments = normalized.split("/").filter(Boolean);
	return segments[segments.length - 1] ?? normalized;
}

export function dirname(path: string) {
	const index = normalizeDisplayPath(path).lastIndexOf("/");
	return index > 0 ? path.slice(0, index) : "";
}

export function splitFileName(name: string) {
	const dotIndex = name.lastIndexOf(".");
	if (dotIndex <= 0) return { name, extension: "" };
	return {
		name: name.slice(0, dotIndex),
		extension: name.slice(dotIndex),
	};
}
