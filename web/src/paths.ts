/** The scheme that serves files of the open folder. Piper refuses a path outside the folder. */
export const ASSET_SCHEME = "piper-asset";

export function dirname(path: string): string {
	const index = path.lastIndexOf("/");
	return index <= 0 ? "" : path.slice(0, index);
}

/** Joins a link target to the folder of a file, and removes `.` and `..` parts. */
export function resolveRelative(fromFile: string, target: string): string | null {
	let decoded = target;
	try {
		decoded = decodeURIComponent(target);
	} catch {
		// Keep the text as written.
	}
	decoded = decoded.split(/[?#]/)[0] ?? "";
	const base = decoded.startsWith("/") ? "" : dirname(fromFile);
	const stack: string[] = [];
	for (const part of `${base}/${decoded}`.split("/")) {
		if (part === "" || part === ".") continue;
		if (part === "..") {
			if (stack.length === 0) return null;
			stack.pop();
			continue;
		}
		stack.push(part);
	}
	return stack.join("/");
}

export function assetURL(path: string): string {
	return `${ASSET_SCHEME}://folder/${path.split("/").map(encodeURIComponent).join("/")}`;
}

/** True for a source that is a file in the folder, not a web or data URL. */
export function isLocalSource(src: string): boolean {
	return src.trim() !== "" && !/^[a-z][a-z0-9+.-]*:/i.test(src) && !src.startsWith("//");
}
