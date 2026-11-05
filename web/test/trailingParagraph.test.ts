import { markdownToTiptapDoc, tiptapDocToMarkdown } from "@hubble.md/editor";
import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import { describe, expect, it } from "vitest";
import { FootnoteDefinition, FootnoteReference } from "../src/Footnote";

// After a transaction, StarterKit adds an empty paragraph after a last block
// that is not a paragraph. A save must not write it as a blank line.
const throughEditor = (markdown: string) => {
	const editor = new Editor({
		element: document.createElement("div"),
		extensions: [StarterKit, FootnoteReference, FootnoteDefinition],
		content: markdownToTiptapDoc(markdown),
	});
	// The page sends a transaction on open, and StarterKit then adds the paragraph.
	editor.view.dispatch(editor.state.tr);
	const out = tiptapDocToMarkdown(editor.getJSON());
	editor.destroy();
	return out;
};

describe("the empty paragraph at the end of the editor", () => {
	it("adds no blank line after a footnote at the end", () => {
		expect(throughEditor("A claim.[^1]\n\n[^1]: The source.")).toBe("A claim.[^1]\n\n[^1]: The source.");
	});

	it("adds no blank line after a list at the end", () => {
		expect(throughEditor("Intro.\n\n- One\n- Two")).toBe("Intro.\n\n- One\n- Two");
	});

	it("adds no blank line after a code block at the end", () => {
		expect(throughEditor("Intro.\n\n```\ncode\n```")).toBe("Intro.\n\n```\ncode\n```");
	});

	it("keeps a paragraph that the file ends with", () => {
		expect(throughEditor("- One\n\nThe end.")).toBe("- One\n\nThe end.");
	});
});
