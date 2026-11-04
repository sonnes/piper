import { Extension } from "@tiptap/core";
import { Plugin, PluginKey } from "@tiptap/pm/state";
import type { EditorView } from "@tiptap/pm/view";
import { Decoration, DecorationSet } from "@tiptap/pm/view";

const headingPlaceholderKey = new PluginKey("HeadingPlaceholderExtension");

function downgradeHeadingAtStart(view: EditorView, emptyOnly = false) {
	const { selection, schema, tr } = view.state;
	if (!selection.empty) return false;
	if (selection.$from.parent.type.name !== "heading") return false;
	if (selection.$from.parentOffset !== 0) return false;
	if (emptyOnly && selection.$from.parent.content.size > 0) return false;

	const paragraph = schema.nodes.paragraph;
	if (!paragraph) return false;

	view.dispatch(tr.setNodeMarkup(selection.$from.before(), paragraph));
	return true;
}

export const HeadingExtension = Extension.create({
	name: "HeadingExtension",
	priority: 2000,

	addKeyboardShortcuts() {
		return {
			Enter: () => downgradeHeadingAtStart(this.editor.view, true),
		};
	},

	addProseMirrorPlugins() {
		return [
			new Plugin({
				key: headingPlaceholderKey,
				props: {
					handleKeyDown(view, event) {
						// Backspace at the start of a heading should remove the heading
						// formatting, not merge with the previous block.
						if (event.key === "Backspace") {
							return downgradeHeadingAtStart(view);
						}
						return false;
					},
					decorations(state) {
						const decorations: Decoration[] = [];

						state.doc.descendants((node, pos) => {
							if (node.type.name !== "heading") return;
							if (node.content.size > 0) return;

							// Use a widget so the ghost text is visible without becoming
							// text that moves the cursor.
							const placeholder = document.createElement("span");
							placeholder.className =
								"pm-ghost-text pm-empty-heading-placeholder";
							placeholder.contentEditable = "false";
							placeholder.textContent = `Heading ${node.attrs.level}`;

							decorations.push(
								Decoration.widget(pos + 1, placeholder, { side: 1 }),
							);
						});

						return DecorationSet.create(state.doc, decorations);
					},
				},
			}),
		];
	},
});
