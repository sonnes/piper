// @vitest-environment happy-dom

import { Editor, type JSONContent } from "@tiptap/core";
import { Table } from "@tiptap/extension-table";
import { TableCell } from "@tiptap/extension-table-cell";
import { TableHeader } from "@tiptap/extension-table-header";
import { TableRow } from "@tiptap/extension-table-row";
import { TextSelection } from "@tiptap/pm/state";
import StarterKit from "@tiptap/starter-kit";
import { afterEach, describe, expect, it } from "vitest";
import { TableCellSelectionExtension } from "./TableCellSelectionExtension";

const editors: Editor[] = [];

afterEach(() => {
	for (const editor of editors) editor.destroy();
	editors.length = 0;
});

describe("table cell selection extension", () => {
	it("selects only the current cell contents for Mod-a inside a table", () => {
		const editor = createTableEditor(tableDoc());
		setCursorInsideText(editor, "one");

		pressSelectAll(editor);

		const { from, to } = editor.state.selection;
		expect(editor.state.doc.textBetween(from, to)).toBe("one");
	});

	it("does not select the document for Mod-a inside an empty table cell", () => {
		const editor = createTableEditor(tableDoc(""));
		setCursorInsideFirstCell(editor);

		pressSelectAll(editor);

		const { from, to } = editor.state.selection;
		expect(from).toBe(to);
		expect(from).toBeGreaterThan(0);
		expect(to).toBeLessThan(editor.state.doc.content.size);
	});
});

function createTableEditor(content: JSONContent) {
	const editor = new Editor({
		element: document.createElement("div"),
		extensions: [
			StarterKit,
			Table.configure({ resizable: true }),
			TableRow,
			TableHeader,
			TableCell,
			TableCellSelectionExtension,
		],
		content,
	});
	editors.push(editor);
	Object.defineProperty(editor, "isFocused", { value: true });
	return editor;
}

function setCursorInsideText(editor: Editor, text: string) {
	let cursorPos: number | null = null;
	editor.state.doc.descendants((node, pos) => {
		if (cursorPos !== null || !node.isText || node.text !== text) return;
		cursorPos = pos + 1;
	});
	if (cursorPos === null) throw new Error(`Could not find text: ${text}`);

	editor.view.dispatch(
		editor.state.tr.setSelection(
			TextSelection.create(editor.state.doc, cursorPos),
		),
	);
}

function setCursorInsideFirstCell(editor: Editor) {
	let cursorPos: number | null = null;
	editor.state.doc.descendants((node, pos) => {
		if (cursorPos !== null) return false;
		if (node.type.name !== "tableCell") return true;
		cursorPos = pos + 2;
		return false;
	});
	if (cursorPos === null) throw new Error("Could not find table cell");

	editor.view.dispatch(
		editor.state.tr.setSelection(
			TextSelection.create(editor.state.doc, cursorPos),
		),
	);
}

function pressSelectAll(editor: Editor) {
	editor.view.dom.dispatchEvent(
		new KeyboardEvent("keydown", {
			key: "a",
			ctrlKey: true,
			bubbles: true,
			cancelable: true,
		}),
	);
}

function tableDoc(firstCellText = "one"): JSONContent {
	return {
		type: "doc",
		content: [
			{
				type: "table",
				content: [
					{
						type: "tableRow",
						content: [cell(firstCellText), cell("two")],
					},
				],
			},
			{
				type: "paragraph",
				content: [{ type: "text", text: "outside" }],
			},
		],
	};
}

function cell(text: string): JSONContent {
	return {
		type: "tableCell",
		content: [
			{
				type: "paragraph",
				content: text ? [{ type: "text", text }] : undefined,
			},
		],
	};
}
