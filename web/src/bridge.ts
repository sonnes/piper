// The message bridge between the page and Piper. Piper calls the functions on
// `window.piper`. The page sends messages to the `editor` handler, and Piper
// answers each message.

import type { WikiTarget } from "@hubble.md/ui";

export type Mode = "rich" | "source";

export type OpenRequest = {
	/** The path of the file, relative to the folder. */
	path: string;
	/** The full text of the file, with the frontmatter. */
	text: string;
	editable: boolean;
	mode: Mode;
	wikiTargets: WikiTarget[];
	/** The byline: the date, the reading time, and the save state. */
	header: string;
	/** The title over a file whose body has no heading. */
	title: string | null;
	anchor: string | null;
};

export type Theme = {
	theme: "Paper" | "Sepia" | "Slate";
	font: "Serif" | "Sans Serif" | "Monospace";
	size: number;
	appearance: "System" | "Light" | "Dark";
};

export type Outgoing =
	| { action: "ready" }
	| { action: "change"; path: string; text: string }
	| { action: "link"; kind: "url" | "wiki"; target: string }
	| { action: "image"; path: string; type: string; data: string }
	| { action: "lossy"; path: string; reasons: string[] }
	| { action: "copy"; text: string }
	// The actions of the selection bar and the margin cards, as in reader.html.
	| { action: "explain" | "define"; anchor: Anchor }
	| { action: "ask"; anchor: Anchor; question: string }
	| { action: "note"; anchor: Anchor; text: string }
	| { action: "capture"; text: string }
	| { action: "open" | "copy" | "continue"; id: string }
	| { action: "followup"; id: string; question: string };

export type Anchor = { quote: string; block: number; offset: number };

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
