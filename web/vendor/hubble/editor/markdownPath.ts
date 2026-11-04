const MARKDOWN_EXTENSION_RE = /\.(md|markdown|mdown)$/i;

export function hasMarkdownExtension(path: string) {
	return MARKDOWN_EXTENSION_RE.test(path);
}

export function stripMarkdownExtension(path: string) {
	return path.replace(MARKDOWN_EXTENSION_RE, "");
}

export function withMarkdownExtension(path: string) {
	const [pathWithoutHash, hash] = path.split("#", 2);
	const pathWithExtension = hasMarkdownExtension(pathWithoutHash)
		? pathWithoutHash
		: `${pathWithoutHash}.md`;
	return hash === undefined
		? pathWithExtension
		: `${pathWithExtension}#${hash}`;
}

export function wikiDisplayNameForTarget(target: string) {
	const withoutHeading = target.split("#")[0] || target;
	const fileName = withoutHeading.split(/[\\/]/).pop() || withoutHeading;
	return stripMarkdownExtension(fileName);
}
