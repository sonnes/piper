// Finds Markdown that the rich editor would change or drop when it saves.
// The editor rewrites the whole file on each save, so a file with such syntax
// opens read-only in the rich editor. The Source mode can still edit it.

import {
	markdownToTiptapDoc,
	parseMarkdownFrontMatter,
	tiptapDocToMarkdown,
} from "@hubble.md/editor";
import type { Root, RootContent } from "mdast";
import remarkGfm from "remark-gfm";
import remarkParse from "remark-parse";
import { unified } from "unified";

const parser = unified().use(remarkParse).use(remarkGfm);

/** Returns the names of the syntax that a save would lose. An empty list means the file is safe. */
export function lossyFeatures(markdown: string): string[] {
	const parsed = parseMarkdownFrontMatter(markdown);
	const body = parsed.body;
	const reasons = new Set<string>();
	const before = parser.parse(body) as Root;
	walk(before, (node) => {
		const reason = unsupported(node);
		if (reason) reasons.add(reason);
	});
	let after: string;
	try {
		after = tiptapDocToMarkdown(markdownToTiptapDoc(body));
	} catch {
		return ["syntax that the editor cannot read"];
	}
	if (signature(before) !== signature(parser.parse(after) as Root)) {
		if (reasons.size === 0) reasons.add("characters that the editor would change");
	}
	return [...reasons];
}

function unsupported(node: RootContent | Root): string | null {
	switch (node.type) {
		case "link":
			return node.title ? "link titles" : null;
		case "image":
			return node.title ? "image titles" : null;
		case "table":
			return node.align?.some((align) => align !== null) ? "table alignment" : null;
		case "definition":
			return node.title ? "link titles" : null;
		default:
			return null;
	}
}

/** The text, the targets, and the structure that a reader sees, with no whitespace. */
function signature(root: Root): string {
	const parts: string[] = [];
	walk(root, (node) => {
		switch (node.type) {
			case "text":
			case "inlineCode":
			case "html":
				parts.push(node.value);
				break;
			case "code":
				parts.push(`code:${node.lang ?? ""}:${node.value}`);
				break;
			case "link":
				parts.push(`link:${node.url}`);
				break;
			case "image":
				parts.push(`image:${node.url}:${node.alt ?? ""}`);
				break;
			case "heading":
				parts.push(`h${node.depth}`);
				break;
			case "emphasis":
			case "strong":
			case "delete":
			case "blockquote":
			case "table":
				parts.push(node.type);
				break;
			case "list":
				parts.push(node.ordered ? "ol" : "ul");
				break;
			case "listItem":
				parts.push(`li:${node.checked ?? ""}`);
				break;
		}
	});
	return parts.join("|").replace(/\s+/g, "");
}

type AnyNode = Root | RootContent;

function walk(node: AnyNode, visit: (node: AnyNode) => void) {
	visit(node);
	if ("children" in node) {
		for (const child of node.children as AnyNode[]) walk(child, visit);
	}
}
