import { selectionToMarkdown } from "@hubble.md/editor";
import type { Editor } from "@tiptap/core";

type CopySelectionAsMarkdownOptions = {
	editor: Editor;
	writeText?: (text: string) => Promise<void>;
	onCopied?: () => void;
};

export async function copySelectionAsMarkdown({
	editor,
	writeText = (text) => navigator.clipboard.writeText(text),
	onCopied,
}: CopySelectionAsMarkdownOptions): Promise<boolean> {
	if (editor.state.selection.empty) {
		return false;
	}

	const markdown = selectionToMarkdown(editor.state.selection).trimEnd();
	if (markdown.length === 0) {
		return false;
	}

	try {
		await writeText(markdown);
		onCopied?.();
		return true;
	} catch {
		return false;
	}
}
