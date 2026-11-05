import { markdownToTiptapDoc, tiptapDocToMarkdown } from "@hubble.md/editor";
import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { describe, expect, it } from "vitest";
import { FootnoteDefinition, FootnoteReference } from "../src/Footnote";
import { lossyFeatures } from "../src/lossGuard";

const roundTrip = (markdown: string) => tiptapDocToMarkdown(markdownToTiptapDoc(markdown));

describe("footnotes", () => {
	it("keeps a reference and its definition", () => {
		const markdown = "A claim.[^1]\n\n[^1]: The source.";
		expect(roundTrip(markdown)).toBe(markdown);
	});

	it("keeps the case of a label", () => {
		const markdown = "A claim.[^Smith2020]\n\n[^Smith2020]: Smith, 2020.";
		expect(roundTrip(markdown)).toBe(markdown);
	});

	it("keeps a definition with two paragraphs", () => {
		const markdown = "A claim.[^1]\n\n[^1]: The first paragraph.\n\n    The second paragraph.";
		expect(roundTrip(markdown)).toBe(markdown);
	});

	it("keeps a definition between other blocks", () => {
		const markdown = "# Title\n\nA claim.[^note]\n\n[^note]: A note with **bold** text.\n\nThe last paragraph.";
		expect(roundTrip(markdown)).toBe(markdown);
	});

	it("keeps a reference inside a formatted span", () => {
		const markdown = "A *claim[^1]* here.\n\n[^1]: The source.";
		expect(roundTrip(markdown)).toBe(markdown);
	});

	it("keeps a reference inside a link", () => {
		const markdown = "[A claim[^1]](https://example.com) here.\n\n[^1]: The source.";
		expect(roundTrip(markdown)).toBe(markdown);
	});

	it("keeps a list inside a definition", () => {
		const markdown = "A claim.[^1]\n\n[^1]: The sources:\n\n    - One\n    - Two";
		expect(roundTrip(markdown)).toBe(markdown);
	});

	it("keeps a reference with no definition as text", () => {
		const markdown = "A claim.[^missing]";
		expect(roundTrip(markdown)).toBe(markdown);
	});

	it("lets the rich editor edit a file with footnotes", () => {
		expect(lossyFeatures("A claim.[^1]\n\n[^1]: The source.\n")).toEqual([]);
	});

	it("makes a reference and a definition as you type", () => {
		const editor = new Editor({
			element: document.createElement("div"),
			extensions: [StarterKit, FootnoteReference, FootnoteDefinition],
			content: "<p></p>",
		});
		const type = (text: string) => {
			for (const character of text) {
				const { from, to } = editor.state.selection;
				const handled = editor.view.someProp("handleTextInput", (handler) =>
					handler(editor.view, from, to, character, () => editor.state.tr.insertText(character, from, to)),
				);
				if (!handled) editor.view.dispatch(editor.state.tr.insertText(character, from, to));
			}
		};
		type("A claim.[^1]");
		editor.commands.splitBlock();
		type("[^1]: The source.");
		expect(tiptapDocToMarkdown(editor.getJSON())).toBe("A claim.[^1]\n\n[^1]: The source.");
		expect(editor.getJSON().content?.map((node) => node.type)).toEqual(["paragraph", "footnoteDefinition", "paragraph"]);
		editor.destroy();
	});

	it("makes a reference right after another reference", () => {
		const editor = new Editor({
			element: document.createElement("div"),
			extensions: [StarterKit, FootnoteReference, FootnoteDefinition],
			content: markdownToTiptapDoc("A claim.[^1]\n\n[^1]: The source."),
		});
		editor.commands.setTextSelection(editor.state.doc.child(0).nodeSize - 1);
		for (const character of " More.[^2][^3]") {
			const { from, to } = editor.state.selection;
			const handled = editor.view.someProp("handleTextInput", (handler) =>
				handler(editor.view, from, to, character, () => editor.state.tr.insertText(character, from, to)),
			);
			if (!handled) editor.view.dispatch(editor.state.tr.insertText(character, from, to));
		}
		expect(tiptapDocToMarkdown(editor.getJSON())).toBe("A claim.[^1] More.[^2][^3]\n\n[^1]: The source.");
		editor.destroy();
	});

	it("makes a second definition under the first", () => {
		const editor = new Editor({
			element: document.createElement("div"),
			extensions: [StarterKit, FootnoteReference, FootnoteDefinition],
			content: markdownToTiptapDoc("A claim.[^1] More.[^2]\n\n[^1]: The source."),
		});
		editor.view.dispatch(editor.state.tr);
		editor.commands.setTextSelection(editor.state.doc.content.size - 1);
		for (const character of "[^2]: The second source.") {
			const { from, to } = editor.state.selection;
			const handled = editor.view.someProp("handleTextInput", (handler) =>
				handler(editor.view, from, to, character, () => editor.state.tr.insertText(character, from, to)),
			);
			if (!handled) editor.view.dispatch(editor.state.tr.insertText(character, from, to));
		}
		expect(tiptapDocToMarkdown(editor.getJSON())).toBe(
			"A claim.[^1] More.[^2]\n\n[^1]: The source.\n\n[^2]: The second source.",
		);
		editor.destroy();
	});

	it("loads into the schema of the editor", () => {
		const editor = new Editor({
			element: document.createElement("div"),
			extensions: [StarterKit, FootnoteReference, FootnoteDefinition],
			content: markdownToTiptapDoc("A claim.[^1]\n\n[^1]: The source."),
		});
		expect(tiptapDocToMarkdown(editor.getJSON())).toBe("A claim.[^1]\n\n[^1]: The source.");
		expect(editor.view.dom.querySelector("sup.piper-footnote-ref")?.textContent).toBe("1");
		expect(editor.view.dom.querySelector("div.piper-footnote")?.getAttribute("data-label")).toBe("1");
		editor.destroy();
	});
});
