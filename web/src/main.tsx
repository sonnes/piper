import { getActiveEditor } from "@hubble.md/ui";
import { createRoot } from "react-dom/client";
import { App } from "./App";
import { type OpenRequest, type PageNote, send, type Theme } from "./bridge";
import { EMBED_CHANGED_EVENT } from "./EmbedNode";
import { lossyFeatures } from "./lossGuard";
import { getState, latestText, setDoc, setState } from "./store";
import { applyTheme } from "./theme";
import "./index.css";

let seq = 0;

const piper = {
	/** Shows a file. A new open starts a new undo history. */
	open(request: OpenRequest) {
		const lossy = lossyFeatures(request.text);
		seq += 1;
		setDoc({ ...request, seq, lossy });
		window.scrollTo(0, 0);
		void send({ action: "lossy", path: request.path, reasons: lossy });
	},

	/** Loads new disk text into the open file, with no undo step. */
	replace(text: string) {
		const doc = getState().doc;
		if (!doc) return;
		const lossy = lossyFeatures(text);
		const next = { ...doc, text, lossy };
		// The source editor reads its text only when it mounts.
		if (doc.mode === "source" || lossy.length !== doc.lossy.length) {
			seq += 1;
			next.seq = seq;
		}
		setDoc(next);
		if (lossy.join() !== doc.lossy.join()) {
			void send({ action: "lossy", path: doc.path, reasons: lossy });
		}
	},

	/** Changes the byline and the title with no new open. */
	header(header: string, title: string | null) {
		const doc = getState().doc;
		if (doc) setState({ doc: { ...doc, header, title } });
	},

	/** Scrolls to a heading of the open file, after the editor shows the file. */
	scrollTo(anchor: string) {
		setState({ scroll: { anchor, seq: (getState().scroll?.seq ?? 0) + 1 } });
	},

	/** The margin notes of the open file: notes, questions, and answers. */
	setNotes(notes: PageNote[]) {
		setState({ notes });
	},

	theme(theme: Theme) {
		applyTheme(theme);
	},

	flush(): string | null {
		return latestText();
	},

	/** Reloads each embed of this file. */
	assetChanged(path: string) {
		window.dispatchEvent(new CustomEvent(EMBED_CHANGED_EVENT, { detail: path }));
	},

	find() {
		getActiveEditor()?.commands.openFind();
	},
};

declare global {
	interface Window {
		piper: typeof piper;
	}
}

window.piper = piper;

// Piper reports each error of the page. Tests read `window.piperErrors`.
const errors: string[] = [];
(window as { piperErrors?: string[] }).piperErrors = errors;
function reportError(message: string) {
	errors.push(message);
	// A report that fails must not report itself again.
	send({ action: "error", message }).catch(() => undefined);
}
window.addEventListener("error", (event) => reportError(String(event.message)));
window.addEventListener("unhandledrejection", (event) => reportError(String(event.reason)));
createRoot(document.getElementById("root") as HTMLElement, {
	onUncaughtError: (error) => reportError(error instanceof Error ? `${error.message}\n${error.stack}` : String(error)),
}).render(<App />);
void send({ action: "ready" });
