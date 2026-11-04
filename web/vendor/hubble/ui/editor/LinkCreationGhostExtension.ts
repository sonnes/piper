import { Extension } from "@tiptap/core";
import { Plugin, PluginKey } from "@tiptap/pm/state";
import { Decoration, DecorationSet } from "@tiptap/pm/view";

type GhostText = { pos: number; text: string };
type GhostTextState = GhostText | undefined;
type GhostTextMeta = GhostTextState | null;

const GHOST_TEXT_CLASS = "pm-ghost-text";

export const linkCreationGhostKey = new PluginKey<GhostTextState>(
	"linkCreationGhost",
);

export const LinkCreationGhostExtension = Extension.create({
	name: "linkCreationGhost",
	addProseMirrorPlugins() {
		return [
			new Plugin<GhostTextState>({
				key: linkCreationGhostKey,
				state: {
					init: () => undefined,
					apply: (tr, prev) => {
						const meta = tr.getMeta(linkCreationGhostKey) as GhostTextMeta;
						if (meta === null) return undefined;
						if (meta !== undefined) return meta;
						if (prev && tr.docChanged) {
							return { ...prev, pos: tr.mapping.map(prev.pos) };
						}
						return prev;
					},
				},
				props: {
					decorations(state) {
						const data = linkCreationGhostKey.getState(state);
						if (!data?.text) return DecorationSet.empty;
						const widget = Decoration.widget(
							data.pos,
							() => {
								const span = document.createElement("span");
								span.className = GHOST_TEXT_CLASS;
								span.textContent = data.text;
								return span;
							},
							{ side: 1 },
						);
						return DecorationSet.create(state.doc, [widget]);
					},
				},
			}),
		];
	},
});
