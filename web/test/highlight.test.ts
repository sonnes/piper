import { markdownToTiptapDoc, tiptapDocToMarkdown } from "@hubble.md/editor";
import { describe, expect, it } from "vitest";
import { lossyFeatures } from "../src/lossGuard";

const roundTrip = (markdown: string) => `${tiptapDocToMarkdown(markdownToTiptapDoc(markdown)).trimEnd()}\n`;

function marks(markdown: string) {
	const doc = markdownToTiptapDoc(markdown);
	const text = doc.content?.[0]?.content ?? [];
	return text.map((node) => [node.text, (node.marks ?? []).map((mark) => `${mark.type}:${mark.attrs?.color ?? ""}`).join(",")]);
}

describe("highlights", () => {
	it("reads == as a yellow highlight", () => {
		expect(marks("A ==key point== here.")).toEqual([
			["A ", ""],
			["key point", "highlight:yellow"],
			[" here.", ""],
		]);
	});

	it("reads a mark tag with a color", () => {
		expect(marks('A <mark class="green">fact</mark>.')).toEqual([
			["A ", ""],
			["fact", "highlight:green"],
			[".", ""],
		]);
	});

	it("keeps other marks inside a highlight", () => {
		expect(roundTrip("==a **bold** word==\n")).toBe("==a **bold** word==\n");
	});

	it("writes each color back", () => {
		expect(roundTrip("==yellow== and <mark class=\"pink\">pink</mark>\n")).toBe(
			"==yellow== and <mark class=\"pink\">pink</mark>\n",
		);
	});

	it("keeps a single == as text", () => {
		expect(roundTrip("if a == b then\n")).toBe("if a == b then\n");
	});

	it("leaves review comments alone", () => {
		expect(roundTrip("{==text==}{>>a comment<<}\n")).toBe("{==text==}{>>a comment<<}\n");
	});

	it("does not mark a file with highlights as lossy", () => {
		expect(lossyFeatures("A ==key point== and <mark class=\"green\">a fact</mark>.\n")).toEqual([]);
	});
});
