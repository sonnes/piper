import { markdownToTiptapDoc } from "@hubble.md/editor";
import { Editor, getSchema } from "@tiptap/core";
import { Node } from "@tiptap/pm/model";
import StarterKit from "@tiptap/starter-kit";
import { act, createElement } from "react";
import { createRoot } from "react-dom/client";
import { describe, expect, it } from "vitest";
import { findQuote, ReaderLayer } from "../src/ReaderLayer";

const schema = getSchema([StarterKit]);

describe("findQuote", () => {
	it("finds a quote across marks and blocks", () => {
		const doc = Node.fromJSON(schema, markdownToTiptapDoc("# Title\n\nOne **bold** passage here.\n"));
		const range = findQuote(doc, "bold passage");
		expect(range).not.toBeNull();
		expect(doc.textBetween(range?.from ?? 0, range?.to ?? 0)).toBe("bold passage");
	});

	it("returns null for a quote that the file no longer holds", () => {
		const doc = Node.fromJSON(schema, markdownToTiptapDoc("Text.\n"));
		expect(findQuote(doc, "gone")).toBeNull();
	});
});

describe("ReaderLayer", () => {
	it("unmounts after its editor is destroyed", async () => {
		(globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT = true;
		const editor = new Editor({ element: document.createElement("div"), extensions: [StarterKit] });
		const viewport = document.createElement("div");
		const root = createRoot(document.createElement("div"));
		await act(async () => root.render(createElement(ReaderLayer, { editor, viewport, notes: [], editable: true })));
		editor.destroy();
		await act(async () => root.unmount());
	});
});
