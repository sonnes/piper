import { getCommandBinding } from "@hubble.md/editor";
import { getActiveEditor } from "@hubble.md/ui";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { scrollToAnchor } from "./anchors";
import { type OpenRequest, send, type Theme } from "./bridge";
import { EMBED_CHANGED_EVENT } from "./EmbedNode";
import { latestText, resetLatest } from "./latest";
import { lossyFeatures } from "./lossGuard";
import type { PageNote } from "./ReaderLayer";
import { getState, setState } from "./store";
import "./index.css";

let seq = 0;

const piper = {
	/** Shows a file. A new open starts a new undo history. */
	open(request: OpenRequest) {
		const lossy = request.editable ? lossyFeatures(request.text) : [];
		resetLatest(request.path, request.text);
		seq += 1;
		setState({ doc: { ...request, seq, lossy } });
		window.scrollTo(0, 0);
		void send({ action: "lossy", path: request.path, reasons: lossy });
	},

	/** Loads new disk text into the open file, with no undo step. */
	replace(text: string) {
		const doc = getState().doc;
		if (!doc) return;
		resetLatest(doc.path, text);
		const lossy = doc.editable ? lossyFeatures(text) : [];
		const next = { ...doc, text, lossy };
		// The source editor reads its text only when it mounts.
		if (doc.mode === "source" || lossy.length !== doc.lossy.length) {
			seq += 1;
			next.seq = seq;
		}
		setState({ doc: next });
		if (lossy.join() !== doc.lossy.join()) {
			void send({ action: "lossy", path: doc.path, reasons: lossy });
		}
	},

	/** Changes the byline and the title with no new open. */
	header(header: string, title: string | null) {
		const doc = getState().doc;
		if (doc) setState({ doc: { ...doc, header, title } });
	},

	scrollTo(anchor: string) {
		scrollToAnchor(document, anchor);
	},

	/** The margin notes of the open file: notes, questions, and answers. */
	setNotes(notes: PageNote[]) {
		setState({ notes });
	},

	theme(theme: Theme) {
		setState({ theme });
	},

	/** Returns the current text of the open file, or null if no file is open. */
	flush(): string | null {
		const doc = getState().doc;
		return doc ? (latestText(doc.path) ?? doc.text) : null;
	},

	/** Reloads each embed of this file. */
	assetChanged(path: string) {
		window.dispatchEvent(new CustomEvent(EMBED_CHANGED_EVENT, { detail: path }));
	},

	command(name: string) {
		const editor = getActiveEditor();
		if (!editor) return;
		if (name === "find") {
			editor.commands.focus();
			const binding = getCommandBinding("app.find") ?? "CmdOrCtrl+F";
			const key = binding.split("+").pop()?.toLowerCase() ?? "f";
			window.dispatchEvent(new KeyboardEvent("keydown", { key, metaKey: true, bubbles: true }));
		}
	},
};

declare global {
	interface Window {
		piper: typeof piper;
	}
}

window.piper = piper;
const errors: string[] = [];
(window as { piperErrors?: string[] }).piperErrors = errors;
window.addEventListener("error", (event) => errors.push(String(event.message)));
window.addEventListener("unhandledrejection", (event) => errors.push(String(event.reason)));
createRoot(document.getElementById("root") as HTMLElement, {
	onUncaughtError: (error) => errors.push(error instanceof Error ? `${error.message}\n${error.stack}` : String(error)),
}).render(<App />);
void send({ action: "ready" });
