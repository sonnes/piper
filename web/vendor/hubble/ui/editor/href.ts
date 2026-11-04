export type HrefKind = "external" | "relative-file";

export function classifyHref(href: string): HrefKind {
	return /^[A-Za-z][A-Za-z0-9+.-]*:/.test(href) ? "external" : "relative-file";
}

export function linkAttrsForHref(href: string) {
	if (classifyHref(href) === "external") {
		return { href, kind: "url" as const, target: null };
	}
	if (href.startsWith("./") || href.startsWith("../") || href.startsWith("/")) {
		return { href, kind: "url" as const, target: null };
	}
	return { href, kind: "wiki" as const, target: href };
}
