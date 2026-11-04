// @vitest-environment happy-dom

import { Editor, type JSONContent } from "@tiptap/core";
import { TextSelection } from "@tiptap/pm/state";
import StarterKit from "@tiptap/starter-kit";
import { afterEach, describe, expect, it } from "vitest";
import {
	applyFormatCommand,
	isFormatActive,
	removeLinksInSelection,
} from "./formatCommands";
import {
	FOCUS_LINK_POPOVER_EVENT,
	SmartLinkExtension,
} from "./SmartLinkExtension";

const editors: Editor[] = [];

afterEach(() => {
	for (const editor of editors) editor.destroy();
	editors.length = 0;
});

describe("applyFormatCommand / isFormatActive", () => {
	it("toggles inline marks on the selection", () => {
		const editor = createEditor(docWithParagraph("hello world"));
		selectText(editor, 1, 6); // "hello"

		applyFormatCommand(editor, "bold");
		expect(isFormatActive(editor, "bold")).toBe(true);
		expect(editor.getJSON()).toMatchObject({
			type: "doc",
			content: [
				{
					type: "paragraph",
					content: [
						{ type: "text", text: "hello", marks: [{ type: "bold" }] },
						{ type: "text", text: " world" },
					],
				},
			],
		});

		applyFormatCommand(editor, "bold");
		expect(isFormatActive(editor, "bold")).toBe(false);
	});

	it("toggles strikethrough on the selection", () => {
		const editor = createEditor(docWithParagraph("hello world"));
		selectText(editor, 1, 6);

		applyFormatCommand(editor, "strike");
		expect(isFormatActive(editor, "strike")).toBe(true);

		applyFormatCommand(editor, "strike");
		expect(isFormatActive(editor, "strike")).toBe(false);
	});

	it("converts the current block to a heading and back to a paragraph", () => {
		const editor = createEditor(docWithParagraph("hello world"));
		selectText(editor, 1, 6);

		applyFormatCommand(editor, "heading2");
		expect(isFormatActive(editor, "heading2")).toBe(true);
		expect(isFormatActive(editor, "paragraph")).toBe(false);
		expect(editor.getJSON().content?.[0]).toMatchObject({
			type: "heading",
			attrs: { level: 2 },
			content: [{ type: "text", text: "hello world" }],
		});

		applyFormatCommand(editor, "paragraph");
		expect(isFormatActive(editor, "paragraph")).toBe(true);
		expect(isFormatActive(editor, "heading2")).toBe(false);
	});
});

describe("link format command", () => {
	it("routes plain selections through the Cmd+K flow", () => {
		const editor = createEditor(docWithParagraph("hello world"));
		selectText(editor, 1, 6); // "hello"

		let popoverFocusRequested = false;
		const onFocusRequest = () => {
			popoverFocusRequested = true;
		};
		window.addEventListener(FOCUS_LINK_POPOVER_EVENT, onFocusRequest);
		applyFormatCommand(editor, "link");
		window.removeEventListener(FOCUS_LINK_POPOVER_EVENT, onFocusRequest);

		// Same code path as Cmd+K: an empty link mark plus a request to open the
		// link popover for editing.
		expect(popoverFocusRequested).toBe(true);
		expect(editor.getJSON().content?.[0]).toMatchObject({
			type: "paragraph",
			content: [
				{
					type: "text",
					text: "hello",
					marks: [{ type: "link", attrs: { href: "" } }],
				},
				{ type: "text", text: " world" },
			],
		});
	});

	it("removes the whole link when the selection is inside one", () => {
		const editor = createEditor(docWithLink());
		selectText(editor, 5, 9); // inside "linked"

		expect(isFormatActive(editor, "link")).toBe(true);
		applyFormatCommand(editor, "link");

		expect(isFormatActive(editor, "link")).toBe(false);
		expect(editor.getJSON().content?.[0]).toMatchObject({
			type: "paragraph",
			content: [{ type: "text", text: "aa linked zz" }],
		});
	});

	it("removes the whole link when the selection only partially overlaps it", () => {
		const editor = createEditor(docWithLink());
		selectText(editor, 2, 6); // spans "a li" across the link boundary

		applyFormatCommand(editor, "link");

		expect(editor.getJSON().content?.[0]).toMatchObject({
			type: "paragraph",
			content: [{ type: "text", text: "aa linked zz" }],
		});
	});

	it("removes a link split across marks as one link", () => {
		const editor = createEditor({
			type: "doc",
			content: [
				{
					type: "paragraph",
					content: [
						{ type: "text", text: "aa " },
						{ type: "text", text: "lin", marks: [linkMark()] },
						{
							type: "text",
							text: "ked",
							marks: [linkMark(), { type: "bold" }],
						},
						{ type: "text", text: " zz" },
					],
				},
			],
		});
		selectText(editor, 4, 6); // inside the plain "lin" segment only

		expect(removeLinksInSelection(editor)).toBe(true);

		// The bold half keeps its bold mark but loses the link too.
		expect(editor.getJSON().content?.[0]).toMatchObject({
			type: "paragraph",
			content: [
				{ type: "text", text: "aa lin" },
				{ type: "text", text: "ked", marks: [{ type: "bold" }] },
				{ type: "text", text: " zz" },
			],
		});
	});

	it("removes the link at a caret inside one", () => {
		const editor = createEditor(docWithLink());
		selectText(editor, 6, 6);

		expect(removeLinksInSelection(editor)).toBe(true);
		expect(editor.getJSON().content?.[0]).toMatchObject({
			type: "paragraph",
			content: [{ type: "text", text: "aa linked zz" }],
		});
	});

	it("leaves links outside the selection untouched", () => {
		const editor = createEditor(docWithLink());
		selectText(editor, 11, 13); // "zz", after the link

		expect(removeLinksInSelection(editor)).toBe(false);
		expect(editor.getJSON().content?.[0]).toMatchObject({
			type: "paragraph",
			content: [
				{ type: "text", text: "aa " },
				{ type: "text", text: "linked", marks: [linkMark()] },
				{ type: "text", text: " zz" },
			],
		});
	});
});

function createEditor(content: JSONContent) {
	const editor = new Editor({
		element: document.createElement("div"),
		extensions: [StarterKit, SmartLinkExtension],
		content,
	});
	editors.push(editor);
	Object.defineProperty(editor, "isFocused", { value: true });
	return editor;
}

function selectText(editor: Editor, from: number, to: number) {
	editor.view.dispatch(
		editor.state.tr.setSelection(
			TextSelection.create(editor.state.doc, from, to),
		),
	);
}

function linkMark() {
	return { type: "link", attrs: { href: "https://example.com" } };
}

function docWithLink(): JSONContent {
	return {
		type: "doc",
		content: [
			{
				type: "paragraph",
				content: [
					{ type: "text", text: "aa " },
					{ type: "text", text: "linked", marks: [linkMark()] },
					{ type: "text", text: " zz" },
				],
			},
		],
	};
}

function docWithParagraph(text: string): JSONContent {
	return {
		type: "doc",
		content: [
			{
				type: "paragraph",
				content: text ? [{ type: "text", text }] : undefined,
			},
		],
	};
}
