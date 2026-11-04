import { describe, expect, it } from "vitest";
import { classifyHref, linkAttrsForHref } from "./href";

describe("classifyHref", () => {
	it("treats hrefs with schemes as external", () => {
		expect(classifyHref("https://example.com")).toBe("external");
		expect(classifyHref("mailto:test@example.com")).toBe("external");
		expect(classifyHref("custom+scheme://value")).toBe("external");
	});

	it("treats bare and rooted paths as relative files", () => {
		expect(classifyHref("./file.md")).toBe("relative-file");
		expect(classifyHref("../file.md")).toBe("relative-file");
		expect(classifyHref("/docs/file.md")).toBe("relative-file");
		expect(classifyHref("file.md")).toBe("relative-file");
	});
});

describe("linkAttrsForHref", () => {
	it("keeps relative markdown-style paths as markdown links", () => {
		expect(linkAttrsForHref("./file.md")).toEqual({
			href: "./file.md",
			kind: "url",
			target: null,
		});
		expect(linkAttrsForHref("../file.md")).toMatchObject({ kind: "url" });
		expect(linkAttrsForHref("/docs/file.md")).toMatchObject({ kind: "url" });
	});

	it("keeps bare names in the wiki flow", () => {
		expect(linkAttrsForHref("notes")).toEqual({
			href: "notes",
			kind: "wiki",
			target: "notes",
		});
	});
});
