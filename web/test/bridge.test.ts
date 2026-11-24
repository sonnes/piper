import { describe, expect, it } from "vitest";
import type { OpenRequest, Outgoing, PageNote, Theme } from "../src/bridge";
import calls from "./fixtures/editor-calls.json";
import messages from "./fixtures/editor-messages.json";
import { type Json, values } from "./json";

// Swift tests decode `editor-messages.json` and encode `editor-calls.json`.
messages satisfies Json<Outgoing>[];
calls satisfies { open: Json<OpenRequest>; themes: Json<Theme>[]; notes: Json<PageNote>[] };

const actions = values<Outgoing["action"]>({
	ready: true,
	change: true,
	link: true,
	image: true,
	lossy: true,
	error: true,
	explain: true,
	define: true,
	ask: true,
	note: true,
	capture: true,
	open: true,
	copy: true,
	continue: true,
	followup: true,
});

describe("editor messages", () => {
	it("have a sample for each action", () => {
		expect(new Set(messages.map((message) => message.action))).toEqual(actions);
	});

	it("have a sample for each kind of link", () => {
		const kinds = messages.flatMap((message) => (message.action === "link" ? [message.kind] : []));
		expect(new Set(kinds)).toEqual(values<Extract<Outgoing, { action: "link" }>["kind"]>({ url: true, wiki: true }));
	});
});

describe("editor calls", () => {
	it("open in a mode of the editor", () => {
		expect(values<OpenRequest["mode"]>({ rich: true, source: true })).toContain(calls.open.mode);
	});

	it("have a theme sample for each theme, font, and appearance", () => {
		expect(new Set(calls.themes.map((theme) => theme.theme))).toEqual(
			values<Theme["theme"]>({ Paper: true, Sepia: true, Slate: true }),
		);
		expect(new Set(calls.themes.map((theme) => theme.font))).toEqual(
			values<Theme["font"]>({ Serif: true, "Sans Serif": true, Monospace: true }),
		);
		expect(new Set(calls.themes.map((theme) => theme.appearance))).toEqual(
			values<Theme["appearance"]>({ System: true, Light: true, Dark: true }),
		);
	});

	it("have a note sample for each kind of note", () => {
		expect(new Set(calls.notes.map((note) => note.kind))).toEqual(
			values<PageNote["kind"]>({ highlight: true, note: true, question: true }),
		);
	});
});
