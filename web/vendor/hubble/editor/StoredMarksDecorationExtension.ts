import { Extension } from "@tiptap/core";
import { type EditorState, Plugin, PluginKey } from "@tiptap/pm/state";
import { Decoration, DecorationSet } from "@tiptap/pm/view";
import { DELIMITER_BY_MARK } from "./MarkdownRolloverExtension.js";

const StoredMarksDecorationKey = new PluginKey("storedMarksDecoration");
const DECORATED_MARKS = ["bold", "italic", "strike"] as const;
type DecoratedMarkName = (typeof DECORATED_MARKS)[number];

/**
 * Shows markdown delimiter widgets at cursor when inline marks are active,
 * but you haven't typed anything yet (i.e. cmd+B on a new line).
 * This gives visible formatting state before typing.
 */
export const StoredMarksDecorationExtension = Extension.create({
	name: "storedMarksDecoration",

	addProseMirrorPlugins() {
		return [
			new Plugin({
				key: StoredMarksDecorationKey,
				props: {
					handleKeyDown: (view, event) => {
						if (event.key !== "Backspace" && event.key !== "Delete") {
							return false;
						}

						const { selection, storedMarks } = view.state;
						if (!selection.empty) return false;

						const marks = storedMarks || selection.$from.marks();
						if (marks.length === 0) return false;
						if (!marks.some((mark) => isDecoratedMarkName(mark.type.name))) {
							return false;
						}
						if (hasAdjacentMarkedText(view.state, DECORATED_MARKS))
							return false;

						const tr = view.state.tr;
						for (const name of DECORATED_MARKS) {
							const markType = view.state.schema.marks[name];
							if (markType) tr.removeStoredMark(markType);
						}
						tr.setStoredMarks(null);
						view.dispatch(tr);
						event.preventDefault();
						return true;
					},
					decorations: (state: EditorState) => {
						const { selection, storedMarks } = state;
						if (!selection.empty) return null;

						const marks = storedMarks || selection.$from.marks();
						if (marks.length === 0) return null;

						const activeMarks = marks
							.map((mark) => mark.type.name)
							.filter(isDecoratedMarkName);
						if (activeMarks.length === 0) return null;
						if (hasAdjacentMarkedText(state, activeMarks)) return null;

						const ordered = DECORATED_MARKS.filter((mark) =>
							activeMarks.includes(mark),
						);
						const leftDelimiter = ordered
							.map((mark) => DELIMITER_BY_MARK[mark]?.start ?? "")
							.join("");
						const rightDelimiter = [...ordered]
							.reverse()
							.map((mark) => DELIMITER_BY_MARK[mark]?.end ?? "")
							.join("");

						const leftWidget = Decoration.widget(
							selection.head,
							() => createDelimiterWidget(leftDelimiter, "start"),
							{ side: -1 },
						);
						const rightWidget = Decoration.widget(
							selection.head,
							() => createDelimiterWidget(rightDelimiter, "end"),
							{ side: 1 },
						);
						return DecorationSet.create(state.doc, [leftWidget, rightWidget]);
					},
				},
			}),
		];
	},
});

function isDecoratedMarkName(name: string): name is DecoratedMarkName {
	return name === "bold" || name === "italic" || name === "strike";
}

/**
 * Creates a non-editable span that represents marks at an empty selection.
 * Ex. Render "****" when bolding without a text selection.
 */
function createDelimiterWidget(delimiter: string, boundary: "start" | "end") {
	const span = document.createElement("span");
	span.className = `pm-md-delimiter pm-md-delimiter-${boundary}`;
	span.contentEditable = "false";
	span.textContent = delimiter;
	return span;
}

function hasAdjacentMarkedText(
	state: EditorState,
	marks: readonly DecoratedMarkName[],
) {
	const { selection } = state;
	const $pos = selection.$from;
	const beforeMarks = $pos.nodeBefore?.marks ?? [];
	const afterMarks = $pos.nodeAfter?.marks ?? [];

	for (const name of marks) {
		const markType = state.schema.marks[name];
		if (!markType) continue;
		if (markType.isInSet(beforeMarks) || markType.isInSet(afterMarks)) {
			return true;
		}
	}
	return false;
}
