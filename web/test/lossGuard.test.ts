import { describe, expect, it } from "vitest";
import { lossyFeatures } from "../src/lossGuard";

describe("lossyFeatures", () => {
	it("passes Markdown that the editor keeps", () => {
		const text = [
			"---",
			"status: draft",
			"---",
			"# Title",
			"",
			"Text with **bold**, *emphasis*, `code`, and a [link](https://example.com).",
			"",
			"- [ ] A task",
			"- [x] A done task",
			"",
			"| A | B |",
			"| --- | --- |",
			"| 1 | 2 |",
			"",
			"See [[Other note|the other note]].",
			"",
		].join("\n");
		expect(lossyFeatures(text)).toEqual([]);
	});

	it("passes Markdown that the editor only normalizes", () => {
		expect(lossyFeatures("* one\n* two\n\n__bold__ and _em_\n")).toEqual([]);
	});

	it("finds footnotes", () => {
		expect(lossyFeatures("A claim.[^1]\n\n[^1]: The source.\n")).toContain("footnotes");
	});

	it("finds link titles", () => {
		expect(lossyFeatures('[a](https://example.com "Title")\n')).toContain("link titles");
	});

	it("finds table alignment", () => {
		expect(lossyFeatures("| A | B |\n| :-- | --: |\n| 1 | 2 |\n")).toContain("table alignment");
	});

	it("finds escaped characters that a save would turn into formatting", () => {
		expect(lossyFeatures("A literal \\*star\\* here.\n")).not.toEqual([]);
	});
});
