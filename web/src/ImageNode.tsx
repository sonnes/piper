// The image node. Adapted from Hubble's apps/desktop/src/editor/ImageExtension.tsx
// and ImageNodeView.tsx (MIT). Piper writes a pasted image next to the note.

import type { Editor } from "@tiptap/core";
import Image from "@tiptap/extension-image";
import { TextSelection } from "@tiptap/pm/state";
import {
	type NodeViewProps,
	NodeViewWrapper,
	ReactNodeViewRenderer,
} from "@tiptap/react";
import { type CSSProperties, useEffect } from "react";
import { send } from "./bridge";
import { assetURL, isLocalSource, resolveRelative } from "./paths";

const uploads = new Map<string, Promise<string>>();

export function createImageExtension(filePath: () => string) {
	return Image.extend({
		group: "block tableCellContent",
		addAttributes() {
			const hidden = { default: null, renderHTML: () => ({}) };
			return {
				...this.parent?.(),
				uploadId: hidden,
				uploadStatus: hidden,
				uploadFile: hidden,
				width: hidden,
				height: hidden,
			};
		},
		addNodeView() {
			return ReactNodeViewRenderer((props: NodeViewProps) => (
				<ImageNodeView {...props} filePath={filePath()} />
			));
		},
	}).configure({ inline: false, allowBase64: true });
}

function ImageNodeView({
	node,
	selected,
	updateAttributes,
	filePath,
}: NodeViewProps & { filePath: string }) {
	const rawSrc = String(node.attrs.src ?? "");
	const uploadId = typeof node.attrs.uploadId === "string" ? node.attrs.uploadId : null;
	const uploadFile = node.attrs.uploadFile instanceof File ? node.attrs.uploadFile : null;
	const measured =
		typeof node.attrs.width === "number" && typeof node.attrs.height === "number";
	const frameStyle = measured
		? ({
				inlineSize: `${node.attrs.width}px`,
				aspectRatio: `${node.attrs.width} / ${node.attrs.height}`,
			} satisfies CSSProperties)
		: undefined;

	useEffect(() => {
		if (!uploadId || !uploadFile || rawSrc) return;
		let cancelled = false;
		void uploadOnce(uploadId, filePath, uploadFile)
			.then((src) => {
				if (!cancelled) {
					updateAttributes({ src, uploadId: null, uploadStatus: null, uploadFile: null });
				}
			})
			.catch(() => {
				if (!cancelled) {
					updateAttributes({ uploadId: null, uploadStatus: "error", uploadFile: null });
				}
			});
		return () => {
			cancelled = true;
		};
	}, [filePath, rawSrc, updateAttributes, uploadFile, uploadId]);

	let shown = rawSrc;
	if (isLocalSource(rawSrc)) {
		const path = resolveRelative(filePath, rawSrc);
		shown = path ? assetURL(path) : "";
	}

	return (
		<NodeViewWrapper as="div" data-drag-handle>
			<div className={measured ? "pm-image-frame pm-image-frame-measured" : "pm-image-frame"} style={frameStyle}>
				{uploadId && !rawSrc ? (
					<div className="pm-image-upload-placeholder">
						<div className="pm-image-upload-placeholder-shimmer" />
					</div>
				) : shown ? (
					<img
						src={shown}
						alt={node.attrs.alt || ""}
						className={selected ? "piper-selected-image" : ""}
					/>
				) : (
					<div className="pm-image-missing">Image unavailable</div>
				)}
			</div>
		</NodeViewWrapper>
	);
}

function uploadOnce(id: string, filePath: string, file: File): Promise<string> {
	const existing = uploads.get(id);
	if (existing) return existing;
	const upload = persist(filePath, file).finally(() => uploads.delete(id));
	uploads.set(id, upload);
	return upload;
}

async function persist(filePath: string, file: File): Promise<string> {
	const data = await base64(file);
	const answer = await send({ action: "image", path: filePath, type: file.type, data });
	if (typeof answer !== "string" || answer.trim() === "") {
		throw new Error("Piper did not save the image.");
	}
	return answer;
}

async function base64(file: File): Promise<string> {
	const bytes = new Uint8Array(await file.arrayBuffer());
	let binary = "";
	for (let index = 0; index < bytes.length; index += 0x8000) {
		binary += String.fromCharCode(...bytes.subarray(index, index + 0x8000));
	}
	return btoa(binary);
}

export function handleImagePaste(editor: Editor, event: ClipboardEvent): boolean {
	const item = Array.from(event.clipboardData?.items ?? []).find((candidate) =>
		candidate.type.startsWith("image/"),
	);
	const file = item?.getAsFile();
	if (!file) return false;
	event.preventDefault();
	void insertUploadImage(editor, file);
	return true;
}

export function handleImageDrop(editor: Editor, event: DragEvent): boolean {
	const file = Array.from(event.dataTransfer?.files ?? []).find((candidate) =>
		candidate.type.startsWith("image/"),
	);
	if (!file) return false;
	event.preventDefault();
	const pos = editor.view.posAtCoords({ left: event.clientX, top: event.clientY })?.pos;
	void insertUploadImage(editor, file, pos);
	return true;
}

async function insertUploadImage(editor: Editor, file: File, pos?: number) {
	const size = await imageSize(file);
	const image = editor.schema.nodes.image?.create({
		src: "",
		alt: "",
		uploadId: `${Date.now()}-${Math.random().toString(36).slice(2)}`,
		uploadStatus: "uploading",
		uploadFile: file,
		width: size.width,
		height: size.height,
	});
	const paragraph = editor.schema.nodes.paragraph?.create();
	if (!image || !paragraph) return;
	const at = pos ?? editor.state.selection.from;
	const tr = editor.state.tr.insert(at, [image, paragraph]);
	editor.view.dispatch(
		tr.setSelection(TextSelection.near(tr.doc.resolve(at + image.nodeSize + 1))),
	);
	editor.commands.focus();
}

function imageSize(file: File): Promise<{ width: number; height: number }> {
	return new Promise((resolve) => {
		const url = URL.createObjectURL(file);
		const img = new window.Image();
		const done = (width: number, height: number) => {
			URL.revokeObjectURL(url);
			const max = 900;
			resolve(width <= max ? { width, height } : { width: max, height: Math.round((height / width) * max) });
		};
		img.onload = () => done(img.naturalWidth || 640, img.naturalHeight || 360);
		img.onerror = () => done(640, 360);
		img.src = url;
	});
}
