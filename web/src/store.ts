import { useSyncExternalStore } from "react";
import type { Mode, OpenRequest, Theme } from "./bridge";
import type { PageNote } from "./ReaderLayer";

export type DocState = OpenRequest & {
	/** Increases on each open, so the editor starts a new undo history. */
	seq: number;
	/** The syntax that the rich editor would drop. Empty when the file is safe to edit. */
	lossy: string[];
};

type State = { doc: DocState | null; theme: Theme | null; notes: PageNote[] };

let state: State = { doc: null, theme: null, notes: [] };
const listeners = new Set<() => void>();

export function getState() {
	return state;
}

export function setState(next: Partial<State>) {
	state = { ...state, ...next };
	for (const listener of listeners) listener();
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

export function setMode(mode: Mode) {
	if (!state.doc) return;
	setState({ doc: { ...state.doc, mode } });
}
