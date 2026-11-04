// @vitest-environment happy-dom

import { LinkExtension, RichTextClipboardExtension } from "@hubble.md/editor";
import { Editor, type JSONContent } from "@tiptap/core";
import { DOMParser } from "@tiptap/pm/model";
import { TextSelection } from "@tiptap/pm/state";
import StarterKit from "@tiptap/starter-kit";
import { afterEach, describe, expect, it } from "vitest";

const editors: Editor[] = [];

afterEach(() => {
	for (const editor of editors) editor.destroy();
	editors.length = 0;
});

describe("rich text clipboard serialization", () => {
	it("serializes linked selections as HTML anchors", () => {
		const editor = createEditor(
			docWithLinkedText("OpenAI", "https://openai.com"),
		);
		selectText(editor, 1, 7);

		const html = serializeSelectionHTML(editor);

		expect(html).toContain("<a");
		expect(html).toContain('href="https://openai.com"');
		expect(html).toContain(">OpenAI</a>");
	});

	it("keeps Hubble link metadata on copied wiki links", () => {
		const editor = createEditor(
			docWithLinkedText("Project note", "Notes/Project.md", {
				kind: "wiki",
				target: "Notes/Project.md",
			}),
		);
		selectText(editor, 1, 13);

		const html = serializeSelectionHTML(editor);

		expect(html).toContain("<a");
		expect(html).toContain('href="Notes/Project.md"');
		expect(html).toContain('data-link-kind="wiki"');
		expect(html).toContain('data-target="Notes/Project.md"');
	});

	it("parses copied wiki anchors back into wiki link marks", () => {
		const editor = createEditor(docWithParagraph("placeholder"));
		const container = document.createElement("div");
		container.innerHTML =
			'<p><a href="Notes/Project.md" data-link-kind="wiki" data-target="Notes/Project.md">Project note</a></p>';

		const parsed = DOMParser.fromSchema(editor.schema).parse(container);

		expect(parsed.toJSON()).toMatchObject({
			type: "doc",
			content: [
				{
					type: "paragraph",
					content: [
						{
							type: "text",
							text: "Project note",
							marks: [
								{
									type: "link",
									attrs: {
										href: "Notes/Project.md",
										kind: "wiki",
										target: "Notes/Project.md",
									},
								},
							],
						},
					],
				},
			],
		});
	});
});

function createEditor(content: JSONContent) {
	const editor = new Editor({
		element: document.createElement("div"),
		extensions: [
			StarterKit.configure({ link: false }),
			LinkExtension,
			RichTextClipboardExtension,
		],
		content,
	});
	editors.push(editor);
	return editor;
}

function selectText(editor: Editor, from: number, to: number) {
	editor.view.dispatch(
		editor.state.tr.setSelection(
			TextSelection.create(editor.state.doc, from, to),
		),
	);
}

function serializeSelectionHTML(editor: Editor) {
	const serializer = editor.view.someProp("clipboardSerializer");
	if (!serializer) throw new Error("Expected clipboard serializer");

	const wrapper = document.createElement("div");
	wrapper.appendChild(
		serializer.serializeFragment(editor.state.selection.content().content, {
			document,
		}),
	);
	return wrapper.innerHTML;
}

function docWithParagraph(text: string): JSONContent {
	return {
		type: "doc",
		content: [
			{
				type: "paragraph",
				content: [{ type: "text", text }],
			},
		],
	};
}

function docWithLinkedText(
	text: string,
	href: string,
	attrs?: { kind?: "url" | "wiki"; target?: string },
): JSONContent {
	return {
		type: "doc",
		content: [
			{
				type: "paragraph",
				content: [
					{
						type: "text",
						text,
						marks: [
							{
								type: "link",
								attrs: {
									href,
									kind: attrs?.kind ?? "url",
									target: attrs?.target ?? null,
								},
							},
						],
					},
				],
			},
		],
	};
}
