import { useSyncExternalStore } from "react";
import type { OpenRequest, PageNote } from "./bridge";

export type DocState = OpenRequest & {
	/** Increases on each open, and on each `replace` that must remount the editor. A new value starts a new undo history. */
	seq: number;
	/** The syntax that the rich editor would drop. Empty when the file is safe to edit. */
	lossy: string[];
};

/** A request to scroll to a heading. `seq` makes each request new, also for the same anchor. */
export type ScrollRequest = { anchor: string; seq: number };

type State = { doc: DocState | null; notes: PageNote[]; scroll: ScrollRequest | null };

let state: State = { doc: null, notes: [], scroll: null };
const listeners = new Set<() => void>();
/** The text of the last edit, which can be newer than `doc.text`. */
let latest: { path: string; text: string } | null = null;

export function getState() {
	return state;
}

export function setState(next: Partial<State>) {
	state = { ...state, ...next };
	for (const listener of listeners) listener();
}

/** Shows a file with new text. The text is the latest text of the file until the next edit. */
export function setDoc(doc: DocState) {
	latest = { path: doc.path, text: doc.text };
	setState({ doc });
}

export function noteLocalChange(path: string, text: string) {
	latest = { path, text };
}

/** The text in the editor now, for `window.piper.flush`. Null when the page shows no file. */
export function latestText(): string | null {
	const { doc } = state;
	if (!doc) return null;
	return latest?.path === doc.path ? latest.text : doc.text;
}

export function useStore(): State {
	return useSyncExternalStore(
		(listener) => {
			listeners.add(listener);
			return () => listeners.delete(listener);
		},
		() => state,
	);
}
