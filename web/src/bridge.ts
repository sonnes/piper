// The message bridge between the page and Piper. Piper calls the functions on
// `window.piper` through `WebPageBridge`. The page sends messages to the
// `editor` handler, and Piper answers each message. `EditorMessage` in Swift
// decodes each message. `web/test/fixtures/editor-messages.json` holds a
// sample of each message, and `web/test/fixtures/editor-calls.json` holds a
// sample of each argument of Piper. A Swift test and a Vitest test read both.

import type { WikiTarget } from "@hubble.md/ui";

export type Mode = "rich" | "source";

export type OpenRequest = {
	/** The path of the file, relative to the folder. */
	path: string;
	/** The full text of the file, with the frontmatter. */
	text: string;
	mode: Mode;
	wikiTargets: WikiTarget[];
	/** The byline: the date, the reading time, and the save state. */
	header: string;
	/** The title over a file whose body has no heading. `open` leaves it out, and `header` sends null. */
	title?: string | null;
};

export type Theme = {
	theme: "Paper" | "Sepia" | "Slate";
	font: "Serif" | "Sans Serif" | "Monospace";
	size: number;
	appearance: "System" | "Light" | "Dark";
	/** The paper color of the theme, as a CSS color for each appearance. */
	background: { light: string; dark: string };
};

/** A margin note from Piper. The fields match `ReaderPageNote` in Swift, which leaves out each nil field. */
export type PageNote = {
	id: string;
	kind: "highlight" | "note" | "question";
	color: string;
	/** The block of the mark. -1 means that the text no longer holds the quote. */
	block: number;
	offset: number;
	length: number;
	quote: string;
	comment: string;
	origin: string;
	label: string;
	turns: { question?: string; answer: string }[];
	pending: boolean;
	failure?: string;
	agent: string;
	tools: string;
};

export type Anchor = { quote: string; block: number; offset: number };

/** An action of the selection bar or a margin card. `ReaderAction` in Swift decodes it. */
export type MarkAction =
	| { action: "explain" | "define"; anchor: Anchor }
	| { action: "ask"; anchor: Anchor; question: string }
	| { action: "note"; anchor: Anchor; text: string }
	| { action: "capture"; text: string }
	| { action: "open" | "copy" | "continue"; id: string }
	| { action: "followup"; id: string; question: string };

export type Outgoing =
	| { action: "ready" }
	| { action: "change"; path: string; text: string }
	| { action: "link"; kind: "url" | "wiki"; target: string }
	| { action: "image"; path: string; type: string; data: string }
	| { action: "lossy"; path: string; reasons: string[] }
	| { action: "error"; message: string }
	| MarkAction;

type Handler = { postMessage(message: unknown): Promise<unknown> };

function handler(): Handler | null {
	const webkit = (window as { webkit?: { messageHandlers?: { editor?: Handler } } })
		.webkit;
	return webkit?.messageHandlers?.editor ?? null;
}

/** Sends a message to Piper and returns the answer. Outside Piper it logs the message. */
export async function send(message: Outgoing): Promise<unknown> {
	const target = handler();
	if (!target) {
		console.info("piper", message);
		return null;
	}
	return target.postMessage(message);
}
