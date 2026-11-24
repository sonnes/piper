import { markdownToTiptapDoc } from "@hubble.md/editor";
import { getSchema } from "@tiptap/core";
import { Node } from "@tiptap/pm/model";
import { EditorState, TextSelection } from "@tiptap/pm/state";
import StarterKit from "@tiptap/starter-kit";
import { describe, expect, it } from "vitest";
import { findQuote, selectedAnchor } from "../src/ReaderLayer";
import samples from "./fixtures/anchors.json";

// The Swift test `testEachAnchorSampleCountsTheSameBlocks` reads the same fixture.
const schema = getSchema([StarterKit]);

/** The range of the copy of a quote with this index, in document order. */
function copy(doc: Node, quote: string, index: number) {
	const ranges: { from: number; to: number }[] = [];
	doc.descendants((node, pos) => {
		if (!node.isText || !node.text) return;
		for (let at = node.text.indexOf(quote); at >= 0; at = node.text.indexOf(quote, at + 1)) {
			ranges.push({ from: pos + at, to: pos + at + quote.length });
		}
	});
	return ranges[index];
}

describe.each(samples)("the anchor of $name", (sample) => {
	const doc = Node.fromJSON(schema, markdownToTiptapDoc(sample.markdown));
	const range = copy(doc, sample.quote, sample.occurrence);

	it("counts the blocks of Swift", () => {
		const selection = TextSelection.create(doc, range.from, range.to);
		expect(selectedAnchor(EditorState.create({ doc, selection }))).toEqual(sample.anchor);
	});

	it("finds the passage of the anchor", () => {
		expect(findQuote(doc, sample.anchor)).toEqual(range);
	});
});
