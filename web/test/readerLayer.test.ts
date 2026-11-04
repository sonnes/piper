import { markdownToTiptapDoc } from "@hubble.md/editor";
import { getSchema } from "@tiptap/core";
import { Node } from "@tiptap/pm/model";
import StarterKit from "@tiptap/starter-kit";
import { describe, expect, it } from "vitest";
import { findQuote } from "../src/ReaderLayer";

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
