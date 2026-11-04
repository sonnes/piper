// The highlight mark: `==text==` in yellow, and green or pink in a `<mark>` tag.
// See vendor/hubble/editor/HighlightMarkdown.ts for the Markdown.

import { Mark, markInputRule, mergeAttributes } from "@tiptap/core";

export const HighlightMark = Mark.create({
	name: "highlight",

	addAttributes() {
		return {
			color: {
				default: "yellow",
				parseHTML: (element) => element.getAttribute("data-color") ?? element.className ?? "yellow",
				renderHTML: (attributes) => ({ "data-color": attributes.color }),
			},
		};
	},

	parseHTML() {
		return [{ tag: "mark" }];
	},

	renderHTML({ HTMLAttributes }) {
		return ["mark", mergeAttributes(HTMLAttributes, { class: "piper-highlight" }), 0];
	},

	addInputRules() {
		return [markInputRule({ find: /(?:^|\s)(==(?!\s+==)([^=]+)==)$/, type: this.type })];
	},
});
