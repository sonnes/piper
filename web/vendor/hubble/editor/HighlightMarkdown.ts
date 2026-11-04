// Piper: highlights in Markdown. `==text==` is a yellow highlight. A green or
// pink highlight is `<mark class="green">text</mark>`, because Markdown has no
// syntax for a color.

import type { Parent, PhrasingContent, Root, Text } from "mdast";
import type { Plugin } from "unified";

export const HIGHLIGHT_COLORS = ["yellow", "green", "pink"] as const;
export type HighlightColor = (typeof HIGHLIGHT_COLORS)[number];

/** The mdast node for a highlight. The parser turns it into a `highlight` mark. */
export type HighlightNode = {
	type: "highlight";
	color: HighlightColor;
	children: PhrasingContent[];
};

const OPEN_TAG = /^<mark(?:\s+class\s*=\s*"(yellow|green|pink)")?\s*>$/i;
const CLOSE_TAG = /^<\/mark\s*>$/i;
// `{==` and `==}` belong to CriticMarkup review comments.
const MARKER = /(?<!\{)==(?!\})/g;

type Open = {
	kind: "equals" | "tag";
	color: HighlightColor;
	raw: PhrasingContent;
	children: PhrasingContent[];
};

export const remarkHighlight: Plugin<[], Root> = () => (tree) => {
	transform(tree as unknown as Parent);
};

function transform(parent: Parent) {
	if (isInlineParent(parent)) {
		parent.children = highlightChildren(parent.children as PhrasingContent[]);
	}
	for (const child of parent.children) {
		if ("children" in child) transform(child as Parent);
	}
}

function isInlineParent(parent: Parent) {
	return parent.children.some(
		(child) => child.type === "text" || child.type === "html",
	);
}

function highlightChildren(children: PhrasingContent[]): PhrasingContent[] {
	const out: PhrasingContent[] = [];
	const stack: Open[] = [];
	const target = () => stack.at(-1)?.children ?? out;
	const close = () => {
		const open = stack.pop();
		if (!open) return;
		const node: HighlightNode = {
			type: "highlight",
			color: open.color,
			children: open.children,
		};
		target().push(node as unknown as PhrasingContent);
	};

	for (const child of children) {
		if (child.type === "html") {
			const value = child.value.trim();
			const opened = OPEN_TAG.exec(value);
			if (opened) {
				stack.push({
					kind: "tag",
					color: (opened[1]?.toLowerCase() as HighlightColor) ?? "yellow",
					raw: child,
					children: [],
				});
				continue;
			}
			if (CLOSE_TAG.test(value) && stack.at(-1)?.kind === "tag") {
				close();
				continue;
			}
			target().push(child);
			continue;
		}
		if (child.type !== "text" || !child.value.includes("==")) {
			target().push(child);
			continue;
		}
		let last = 0;
		for (const match of child.value.matchAll(MARKER)) {
			const before = child.value.slice(last, match.index);
			if (before) target().push(text(before));
			last = (match.index ?? 0) + 2;
			if (stack.at(-1)?.kind === "equals") {
				close();
			} else {
				stack.push({ kind: "equals", color: "yellow", raw: text("=="), children: [] });
			}
		}
		const rest = child.value.slice(last);
		if (rest) target().push(text(rest));
	}

	// A marker without its pair stays as the text that it was.
	while (stack.length > 0) {
		const open = stack.pop() as Open;
		target().push(open.raw, ...open.children);
	}
	return mergeText(out);
}

function text(value: string): Text {
	return { type: "text", value };
}

function mergeText(nodes: PhrasingContent[]): PhrasingContent[] {
	const out: PhrasingContent[] = [];
	for (const node of nodes) {
		const previous = out.at(-1);
		if (node.type === "text" && previous?.type === "text") {
			out[out.length - 1] = text(previous.value + node.value);
		} else {
			out.push(node);
		}
	}
	return out;
}

/** The opening and the closing Markdown of a highlight. */
export function highlightDelimiters(color: unknown): [string, string] {
	if (color === "green" || color === "pink") {
		return [`<mark class="${color}">`, "</mark>"];
	}
	return ["==", "=="];
}
