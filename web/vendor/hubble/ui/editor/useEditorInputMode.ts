import type { Editor } from "@tiptap/core";
import { type RefObject, useEffect, useState } from "react";

export type EditorInputMode = "pointer" | "keyboard";

export function useEditorInputMode({
	editor,
	containerRef,
}: {
	editor: Editor | null;
	containerRef: RefObject<HTMLDivElement | null>;
}) {
	const [inputMode, setInputMode] = useState<EditorInputMode>("keyboard");

	useEffect(() => {
		const setMode = (nextMode: EditorInputMode) => {
			setInputMode(nextMode);
		};

		const isEditorRelatedEvent = (target: EventTarget | null) => {
			const container = containerRef.current;
			if (!container) return Boolean(editor?.isFocused);
			if (!(target instanceof Node)) return Boolean(editor?.isFocused);
			return container.contains(target) || Boolean(editor?.isFocused);
		};

		const onPointerDown = (event: MouseEvent) => {
			if (!isEditorRelatedEvent(event.target)) return;
			setMode("pointer");
		};
		const onKeyDown = (event: KeyboardEvent) => {
			if (!isEditorRelatedEvent(event.target)) return;
			setMode("keyboard");
		};

		window.addEventListener("mousedown", onPointerDown, true);
		window.addEventListener("keydown", onKeyDown, true);

		return () => {
			window.removeEventListener("mousedown", onPointerDown, true);
			window.removeEventListener("keydown", onKeyDown, true);
		};
	}, [editor, containerRef]);

	return {
		inputMode,
	};
}
