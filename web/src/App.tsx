import { EditorView, getActiveEditor, MarkdownSourceEditor } from "@hubble.md/ui";
import type { Editor } from "@tiptap/react";
import { useEffect, useMemo, useRef, useState } from "react";
import { scrollToAnchor } from "./anchors";
import { send } from "./bridge";
import { createEmbedExtension } from "./EmbedNode";
import { HighlightMark } from "./HighlightMark";
import { createImageExtension, handleImageDrop, handleImagePaste } from "./ImageNode";
import { noteLocalChange } from "./latest";
import { QuestionMarks, ReaderLayer } from "./ReaderLayer";
import { useStore } from "./store";
import { applyTheme } from "./theme";

export function App() {
	const { doc, theme, notes } = useStore();
	const [viewport, setViewport] = useState<HTMLDivElement | null>(null);
	const [editor, setEditor] = useState<Editor | null>(null);
	const pathRef = useRef(doc?.path ?? "");
	pathRef.current = doc?.path ?? "";
	const extensions = useMemo(
		() => [
			createImageExtension(() => pathRef.current),
			createEmbedExtension(() => pathRef.current),
			HighlightMark,
			QuestionMarks,
		],
		[],
	);

	useEffect(() => {
		if (theme) applyTheme(theme);
	}, [theme]);

	// The editor of the page changes with each open. The reader layer needs the current one.
	// biome-ignore lint/correctness/useExhaustiveDependencies: a new open makes a new editor
	useEffect(() => {
		const id = window.setTimeout(() => setEditor(getActiveEditor()), 0);
		return () => window.clearTimeout(id);
	}, [doc?.seq, doc?.mode, viewport]);

	useEffect(() => {
		if (!doc?.anchor) return;
		const id = window.setTimeout(() => scrollToAnchor(document, doc.anchor ?? ""), 0);
		return () => window.clearTimeout(id);
	}, [doc?.seq, doc?.anchor]);

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
					onSave={doc.editable ? save : () => {}}
				/>
			</div>
		);
	}

	const editable = doc.editable && doc.lossy.length === 0;
	return (
		<>
		<EditorView
			key={`rich-${doc.seq}`}
			path={doc.path}
			initialMarkdown={doc.text}
			editable={editable}
			selectionToolbar={false}
			onScrollContainerChange={setViewport}
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
