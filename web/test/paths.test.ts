import { describe, expect, it } from "vitest";
import { anchor, headingAnchors } from "../src/anchors";
import { assetURL, isLocalSource, resolveRelative } from "../src/paths";

describe("resolveRelative", () => {
	it("resolves from the folder of the file", () => {
		expect(resolveRelative("notes/a.md", "img/b.png")).toBe("notes/img/b.png");
		expect(resolveRelative("notes/a.md", "../b.png")).toBe("b.png");
		expect(resolveRelative("a.md", "a.assets/x%20y.png")).toBe("a.assets/x y.png");
	});

	it("resolves a path with a leading slash from the folder root", () => {
		expect(resolveRelative("notes/a.md", "/img/b.png")).toBe("img/b.png");
	});

	it("refuses a path that leaves the folder", () => {
		expect(resolveRelative("a.md", "../../etc/passwd")).toBeNull();
	});
});

describe("assets", () => {
	it("encodes each path part", () => {
		expect(assetURL("a b/c#d.png")).toBe("piper-asset://folder/a%20b/c%23d.png");
	});

	it("treats only relative paths as local", () => {
		expect(isLocalSource("img.png")).toBe(true);
		expect(isLocalSource("https://example.com/a.png")).toBe(false);
		expect(isLocalSource("data:image/png;base64,AA")).toBe(false);
		expect(isLocalSource("//example.com/a.png")).toBe(false);
	});
});

describe("anchor", () => {
	it("matches the anchors of Piper", () => {
		expect(anchor("Request path")).toBe("request-path");
		expect(anchor("What's next?")).toBe("whats-next");
	});

	it("numbers a repeated heading", () => {
		expect(headingAnchors(["Repeat", "Other", "Repeat", "Repeat"])).toEqual([
			"repeat",
			"other",
			"repeat-1",
			"repeat-2",
		]);
	});
});
