import { type Editor, Extension } from "@tiptap/core";
import type { Node as ProseMirrorNode } from "@tiptap/pm/model";
import { TextSelection } from "@tiptap/pm/state";

export const TableCellSelectionExtension = Extension.create({
	name: "tableCellSelection",
	priority: 1000,

	addKeyboardShortcuts() {
		return {
			"Mod-a": () => selectCurrentCellContents(this.editor),
		};
	},
});

function selectCurrentCellContents(editor: Editor) {
	const { doc, selection } = editor.state;
	const { $from } = selection;

	for (let depth = $from.depth; depth > 0; depth--) {
		const node = $from.node(depth);
		if (node.type.name !== "tableCell" && node.type.name !== "tableHeader") {
			continue;
		}

		const range = textRangeInCell(node, $from.before(depth) + 1);
		if (range) {
			editor.view.dispatch(
				editor.state.tr.setSelection(
					TextSelection.create(doc, range.from, range.to),
				),
			);
		}
		return true;
	}

	return false;
}

function textRangeInCell(cell: ProseMirrorNode, cellContentStart: number) {
	let from: number | null = null;
	let to: number | null = null;

	cell.descendants((node, pos) => {
		if (!node.isText || !node.text) return;
		const start = cellContentStart + pos;
		from ??= start;
		to = start + node.nodeSize;
	});

	return from === null || to === null ? null : { from, to };
}
