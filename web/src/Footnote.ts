// Markdown footnotes: a `[^label]` reference in the text, and a
// `[^label]: text` definition as a block. See
// vendor/hubble/editor/markdownToProsemirror.ts and prosemirrorToMarkdown.ts
// for the Markdown.

import { mergeAttributes, Node, nodeInputRule, wrappingInputRule } from "@tiptap/core";

const label = {
	default: "",
	parseHTML: (element: HTMLElement) => element.getAttribute("data-label") ?? "",
	renderHTML: (attributes: Record<string, unknown>) => ({ "data-label": attributes.label }),
};

export const FootnoteReference = Node.create({
	name: "footnoteReference",
	group: "inline",
	inline: true,
	atom: true,
	selectable: true,

	addAttributes() {
		return { label };
	},

	parseHTML() {
		return [{ tag: "sup.piper-footnote-ref" }];
	},

	renderHTML({ node, HTMLAttributes }) {
		return ["sup", mergeAttributes(HTMLAttributes, { class: "piper-footnote-ref" }), String(node.attrs.label)];
	},

	renderText({ node }) {
		return `[^${node.attrs.label}]`;
	},

	// `[^1]` right after a word. At the start of a line, the text can still become a definition.
	addInputRules() {
		return [
			nodeInputRule({
				find: /\S(\[\^[^\]\s]+\])$/,
				type: this.type,
				getAttributes: (match) => ({ label: match[1].slice(2, -1) }),
			}),
		];
	},
});

export const FootnoteDefinition = Node.create({
	name: "footnoteDefinition",
	group: "block",
	content: "block+",
	defining: true,

	addAttributes() {
		return { label };
	},

	parseHTML() {
		return [{ tag: "div.piper-footnote" }];
	},

	renderHTML({ HTMLAttributes }) {
		return ["div", mergeAttributes(HTMLAttributes, { class: "piper-footnote" }), 0];
	},

	// `[^1]: ` at the start of a line.
	addInputRules() {
		return [
			wrappingInputRule({
				find: /^\[\^([^\]\s]+)\]:\s$/,
				type: this.type,
				getAttributes: (match) => ({ label: match[1] }),
				// Each definition stays its own block, under the one before it.
				joinPredicate: () => false,
			}),
		];
	},
});
