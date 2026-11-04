// An HTML file of the folder in a sandboxed iframe. Adapted from Hubble's
// apps/desktop/src/editor/EmbedExtension.tsx (MIT), without the file broker:
// an embed cannot read or write the folder.

import { Node } from "@tiptap/core";
import { NodeViewWrapper, ReactNodeViewRenderer } from "@tiptap/react";
import { useEffect, useState } from "react";
import { assetURL, resolveRelative } from "./paths";

export const EMBED_CHANGED_EVENT = "piper:embed-changed";

export function createEmbedExtension(filePath: () => string) {
	return Node.create({
		name: "embed",
		group: "block",
		atom: true,
		selectable: true,
		draggable: true,
		addAttributes() {
			return { kind: { default: "iframe" }, src: { default: "" } };
		},
		renderHTML({ node }) {
			return ["iframe", { src: String(node.attrs.src ?? "") }];
		},
		addNodeView() {
			return ReactNodeViewRenderer(({ node }) => (
				<EmbedView src={String(node.attrs.src ?? "")} filePath={filePath()} />
			));
		},
	});
}

function EmbedView({ src, filePath }: { src: string; filePath: string }) {
	const path = resolveRelative(filePath, src);
	const [version, setVersion] = useState(0);

	useEffect(() => {
		const changed = (event: Event) => {
			if ((event as CustomEvent<string>).detail === path) setVersion((value) => value + 1);
		};
		window.addEventListener(EMBED_CHANGED_EVENT, changed);
		return () => window.removeEventListener(EMBED_CHANGED_EVENT, changed);
	}, [path]);

	return (
		<NodeViewWrapper as="div" className="piper-embed" data-drag-handle>
			{path ? (
				<iframe
					key={version}
					title={src}
					src={assetURL(path)}
					sandbox="allow-scripts allow-forms"
					referrerPolicy="no-referrer"
				/>
			) : (
				<div className="pm-image-missing">This embed is outside the folder.</div>
			)}
		</NodeViewWrapper>
	);
}
