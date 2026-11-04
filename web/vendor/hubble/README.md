# Hubble Source

This folder holds a copy of source from [Hubble.md](https://github.com/bholmesdev/hubble.md), commit `a9734517f86ba9b341544fb2b8600bdf873ba415`, under the MIT license in `LICENSE`.

| Folder | Source |
| --- | --- |
| `editor/` | `packages/editor/src` |
| `ui/` | `packages/ui/src` |

Local changes:

- `ui/editor/EditorView.tsx`: a `header` prop that shows content at the top of the scroll area, a `selectionToolbar` prop that hides the formatting toolbar, and StarterKit's Underline turned off.
- `editor/HighlightMarkdown.ts` (new): `==text==` and `<mark class="green">` highlights. `markdownToProsemirror.ts` and `prosemirrorToMarkdown.ts` read and write them.
