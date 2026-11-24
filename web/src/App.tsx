import { EditorView, MarkdownSourceEditor } from "@hubble.md/ui";
import type { Editor } from "@tiptap/core";
import { useEffect, useMemo, useState } from "react";
import { scrollToAnchor } from "./anchors";
import { send } from "./bridge";
import { createEmbedExtension } from "./EmbedNode";
import { FootnoteDefinition, FootnoteReference } from "./Footnote";
import { HighlightMark } from "./HighlightMark";
import { createImageExtension, handleImageDrop, handleImagePaste } from "./ImageNode";
import { QuestionMarks, ReaderLayer } from "./ReaderLayer";
import { noteLocalChange, useStore } from "./store";

export function App() {
	const { doc, notes, scroll } = useStore();
	const [viewport, setViewport] = useState<HTMLDivElement | null>(null);
	const [editor, setEditor] = useState<Editor | null>(null);
	const path = doc?.path ?? "";
	const extensions = useMemo(
		() => [
			createImageExtension(() => path),
			createEmbedExtension(() => path),
			HighlightMark,
			FootnoteReference,
			FootnoteDefinition,
			QuestionMarks,
		],
		[path],
	);

	useEffect(() => {
		if (!scroll) return;
		const id = window.setTimeout(() => scrollToAnchor(document, scroll.anchor), 0);
		return () => window.clearTimeout(id);
	}, [scroll]);

	if (!doc) return null;

	const save = (path: string, text: string) => {
		void send({ action: "change", path, text });
	};
	const header = (
		<div className="piper-header">
			{doc.header ? <div className="piper-byline">{doc.header}</div> : null}
			{doc.title ? <div className="piper-title">{doc.title}</div> : null}
		</div>
	);

	if (doc.mode === "source") {
		return (
			<div className="piper-source">
				{header}
				<MarkdownSourceEditor
					key={`source-${doc.seq}`}
					path={doc.path}
					initialMarkdown={doc.text}
					autoFocus={false}
					onLocalChange={noteLocalChange}
					onSave={save}
				/>
			</div>
		);
	}

	const editable = doc.lossy.length === 0;
	return (
		<>
		<EditorView
			key={`rich-${doc.seq}`}
			path={doc.path}
			initialMarkdown={doc.text}
			editable={editable}
			selectionToolbar={false}
			onScrollContainerChange={setViewport}
			onEditorChange={setEditor}
			wikiTargets={doc.wikiTargets}
			extensions={extensions}
			header={header}
			onPaste={handleImagePaste}
			onDrop={handleImageDrop}
			onLocalChange={noteLocalChange}
			onSave={save}
			onOpenExternalLink={(target) => {
				void send({ action: "link", kind: "url", target });
			}}
			onOpenWikiLink={(target) => {
				void send({ action: "link", kind: "wiki", target });
			}}
		/>
		<ReaderLayer editor={editor} viewport={viewport} notes={notes} editable={editable} />
		</>
	);
}
