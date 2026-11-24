// The selection bar and the margin cards of the Reader tab, in the editor.
// Ported from Sources/Piper/Resources/reader.html. A highlight goes into the
// file. A note, a question, and an answer are notes in Piper, which the margin
// cards show.

import { Extension } from "@tiptap/core";
import type { Node as PMNode } from "@tiptap/pm/model";
import { type EditorState, Plugin, PluginKey } from "@tiptap/pm/state";
import { Decoration, DecorationSet } from "@tiptap/pm/view";
import type { Editor } from "@tiptap/core";
import { type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { type Anchor, type PageNote, send } from "./bridge";

const CARD_WIDTH = 250;
const CARD_GAP = 36;
const COLUMN = 736;

/** A run of the text of a block. A gap separates two paragraphs of one block, or stands for a line break. */
type Segment = { pos: number; text: string; gap: boolean };

/** One block of a note anchor. `WikiMarkdown.textBlocks` in Swift counts the same blocks. */
type TextBlock = { kind: string; text: string; segments: Segment[] };

const LISTS = new Set(["bulletList", "orderedList"]);
const MEDIA = new Set(["image", "embed"]);
const WHOLE = new Set(["blockquote", "table", "footnoteDefinition"]);

function collect(node: PMNode, pos: number, separator: string, segments: Segment[]) {
	if (node.isTextblock) {
		if (segments.length > 0) segments.push({ pos: pos + 1, text: separator, gap: true });
		node.forEach((child, offset) => {
			if (child.isText && child.text) segments.push({ pos: pos + 1 + offset, text: child.text, gap: false });
			else if (child.type.name === "hardBreak") segments.push({ pos: pos + 1 + offset, text: " ", gap: true });
		});
		return;
	}
	node.forEach((child, offset) => collect(child, pos + 1 + offset, separator, segments));
}

/**
 * The text blocks of a document in order, with the rule of `WikiMarkdown.parse`:
 * one block for each heading, paragraph, code block, list item, quote, table,
 * footnote, image, and embed. A list item does not hold its nested list. A
 * block with no text is left out, except an image or an embed, which has
 * Markdown text in Swift.
 */
export function textBlocks(doc: PMNode): TextBlock[] {
	const blocks: TextBlock[] = [];
	const add = (kind: string, segments: Segment[]) => {
		const text = segments.map((segment) => segment.text).join("");
		if (text.trim() || MEDIA.has(kind)) blocks.push({ kind, text, segments });
	};
	const walk = (node: PMNode, pos: number) => {
		let previous = "";
		node.forEach((child, offset) => {
			const at = pos + offset;
			const name = child.type.name;
			if (LISTS.has(name)) {
				walk(child, at + 1);
			} else if (name === "listItem") {
				const own: Segment[] = [];
				const nested: [PMNode, number][] = [];
				child.forEach((part, partOffset) => {
					if (LISTS.has(part.type.name)) nested.push([part, at + 1 + partOffset]);
					else collect(part, at + 1 + partOffset, " ", own);
				});
				add(name, own);
				for (const [list, listPos] of nested) walk(list, listPos + 1);
			} else if (WHOLE.has(name)) {
				const segments: Segment[] = [];
				collect(child, at, "\n", segments);
				const last = blocks.at(-1);
				// Swift joins a quote to the quote before it.
				if (name === "blockquote" && previous === name && last?.kind === name && segments.length > 0) {
					last.segments.push({ pos: segments[0].pos, text: "\n", gap: true }, ...segments);
					last.text = last.segments.map((segment) => segment.text).join("");
				} else {
					add(name, segments);
				}
			} else if (child.isTextblock) {
				const segments: Segment[] = [];
				collect(child, at, " ", segments);
				add(name, segments);
			} else if (MEDIA.has(name)) {
				add(name, []);
			} else if (!child.isLeaf) {
				walk(child, at + 1);
			}
			previous = name;
		});
	};
	walk(doc, 0);
	return blocks;
}

/** The document position of an offset in a block. A start lies after a gap, and an end lies before it. */
function position(block: TextBlock, offset: number, isEnd: boolean) {
	let rest = offset;
	for (const segment of block.segments) {
		if (rest < segment.text.length || (isEnd && rest === segment.text.length)) {
			return segment.gap ? segment.pos : segment.pos + rest;
		}
		rest -= segment.text.length;
	}
	const last = block.segments.at(-1);
	return last ? last.pos + (last.gap ? 0 : last.text.length) : 0;
}

function offsetOf(block: TextBlock, pos: number) {
	let offset = 0;
	for (const segment of block.segments) {
		if (pos < segment.pos) return offset;
		if (!segment.gap && pos <= segment.pos + segment.text.length) return offset + pos - segment.pos;
		offset += segment.text.length;
	}
	return offset;
}

function end(block: TextBlock) {
	const last = block.segments.at(-1);
	return last ? last.pos + (last.gap ? 0 : last.text.length) : -1;
}

/**
 * The document range of a note. The stored block and offset win when they
 * still hold the quote. If not, the first match in the stored block wins, then
 * the first match in the document. `NoteAnchor.locate` in Swift has the same
 * order, and then also looks for a quote that spans blocks. This function does
 * not, so such a note gets no mark in the editor.
 */
export function findQuote(doc: PMNode, anchor: Anchor): { from: number; to: number } | null {
	const { quote } = anchor;
	if (!quote) return null;
	const blocks = textBlocks(doc);
	const range = (block: TextBlock, at: number) => ({
		from: position(block, at, false),
		to: position(block, at + quote.length, true),
	});
	const stored = blocks[anchor.block];
	if (stored) {
		if (anchor.offset >= 0 && stored.text.startsWith(quote, anchor.offset)) return range(stored, anchor.offset);
		const at = stored.text.indexOf(quote);
		if (at >= 0) return range(stored, at);
	}
	for (const block of blocks) {
		const at = block.text.indexOf(quote);
		if (at >= 0) return range(block, at);
	}
	return null;
}

/** The quote, the block, and the offset of the selection, clipped to its first block. */
export function selectedAnchor(state: EditorState): Anchor | null {
	const { from, to, empty } = state.selection;
	if (empty) return null;
	const blocks = textBlocks(state.doc);
	const block = blocks.findIndex((item) => end(item) > from);
	if (block < 0) return null;
	const item = blocks[block];
	const start = offsetOf(item, from);
	const raw = item.text.slice(start, offsetOf(item, to));
	const quote = raw.trim();
	if (!quote) return null;
	return { quote, block, offset: start + raw.length - raw.trimStart().length };
}

type Questions = { notes: PageNote[]; decorations: DecorationSet };

const questionKey = new PluginKey<Questions>("piperQuestions");

function decorations(doc: PMNode, notes: PageNote[]) {
	const items = notes.flatMap((note) => {
		const range = findQuote(doc, note);
		return range ? [Decoration.inline(range.from, range.to, { class: "piper-question", "data-n": note.id })] : [];
	});
	return DecorationSet.create(doc, items);
}

/** Underlines the passage of each question. A transaction with the questions as its meta changes them. */
export const QuestionMarks = Extension.create({
	name: "piperQuestions",
	addProseMirrorPlugins() {
		return [
			new Plugin<Questions>({
				key: questionKey,
				state: {
					init: () => ({ notes: [], decorations: DecorationSet.empty }),
					apply: (tr, value) => {
						const notes = (tr.getMeta(questionKey) as PageNote[] | undefined) ?? value.notes;
						if (!tr.docChanged && notes === value.notes) return value;
						return { notes, decorations: decorations(tr.doc, notes) };
					},
				},
				props: { decorations: (state) => questionKey.getState(state)?.decorations },
			}),
		];
	},
});

export function ReaderLayer({
	editor,
	viewport,
	notes,
	editable,
}: {
	editor: Editor | null;
	viewport: HTMLDivElement | null;
	notes: PageNote[];
	editable: boolean;
}) {
	const cards = notes.filter((note) => note.kind === "question" || note.kind === "note");
	const wide = useWide(viewport, cards.length > 0);

	useEffect(() => {
		if (!editor || editor.isDestroyed) return;
		const questions = notes.filter((note) => note.kind === "question");
		editor.view.dispatch(editor.state.tr.setMeta(questionKey, questions));
	}, [editor, notes]);

	if (!editor || !viewport) return null;
	return createPortal(
		<>
			<SelectionBar editor={editor} viewport={viewport} editable={editable} />
			<MarginCards editor={editor} viewport={viewport} cards={cards} wide={wide} />
		</>,
		viewport,
	);
}

/** True when the pane has room for the margin beside the column. Moves the column to make room. */
function useWide(viewport: HTMLDivElement | null, hasCards: boolean) {
	const [wide, setWide] = useState(false);
	useLayoutEffect(() => {
		if (!viewport) return;
		const update = () => {
			const width = viewport.clientWidth;
			const room = hasCards && width >= 480 + CARD_WIDTH + CARD_GAP + 48;
			setWide(room);
			viewport.classList.toggle("piper-has-margin", room);
			if (room) {
				const column = Math.min(COLUMN, width - CARD_WIDTH - CARD_GAP - 24);
				const left = Math.max(0, (width - column - CARD_WIDTH - CARD_GAP) / 2);
				viewport.style.setProperty("--piper-column", `${column}px`);
				viewport.style.setProperty("--piper-column-left", `${left}px`);
			}
		};
		update();
		const observer = new ResizeObserver(update);
		observer.observe(viewport);
		return () => {
			observer.disconnect();
			viewport.classList.remove("piper-has-margin");
		};
	}, [viewport, hasCards]);
	return wide;
}

type Line = { kind: "ask" | "note"; anchor: Anchor } | null;

function SelectionBar({ editor, viewport, editable }: { editor: Editor; viewport: HTMLDivElement; editable: boolean }) {
	const [place, setPlace] = useState<{ left: number; top: number } | null>(null);
	const [line, setLine] = useState<Line>(null);
	const [input, setInput] = useState("");
	const barRef = useRef<HTMLDivElement | null>(null);

	useEffect(() => {
		const show = () => {
			window.setTimeout(() => {
				if (editor.isDestroyed || !selectedAnchor(editor.state)) {
					setPlace(null);
					return;
				}
				const { from, to } = editor.state.selection;
				const start = editor.view.coordsAtPos(from);
				const end = editor.view.coordsAtPos(to);
				const box = viewport.getBoundingClientRect();
				const width = barRef.current?.offsetWidth ?? 420;
				const middle = (start.left + (start.top === end.top ? end.left : start.left)) / 2 - box.left;
				setPlace({
					left: Math.max(8, Math.min(middle - width / 2, viewport.clientWidth - width - 8)),
					top: Math.max(start.top - box.top + viewport.scrollTop - 44, viewport.scrollTop + 4),
				});
			});
		};
		const hide = () => {
			if (editor.state.selection.empty) setPlace(null);
		};
		const shifted = (event: KeyboardEvent) => {
			if (event.shiftKey) show();
		};
		const dom = editor.view.dom;
		dom.addEventListener("mouseup", show);
		dom.addEventListener("keyup", shifted);
		editor.on("selectionUpdate", hide);
		return () => {
			dom.removeEventListener("mouseup", show);
			dom.removeEventListener("keyup", shifted);
			editor.off("selectionUpdate", hide);
		};
	}, [editor, viewport]);

	const close = () => {
		setPlace(null);
		setLine(null);
		setInput("");
	};

	const act = (action: "explain" | "define" | "ask" | "note" | "capture") => {
		const anchor = selectedAnchor(editor.state);
		if (!anchor) return close();
		if (action === "ask" || action === "note") {
			setLine({ kind: action, anchor });
			setInput("");
			return;
		}
		if (action === "capture") void send({ action: "capture", text: anchor.quote });
		else void send({ action, anchor });
		collapse();
		close();
	};

	const highlight = (color: string) => {
		const active = editor.getAttributes("highlight").color;
		if (active === color) editor.chain().focus().unsetMark("highlight").run();
		else editor.chain().focus().setMark("highlight", { color }).run();
		collapse();
		close();
	};

	const collapse = () => {
		const { to } = editor.state.selection;
		editor.chain().setTextSelection(to).run();
	};

	const submit = () => {
		const text = input.trim();
		if (!text || !line) return;
		if (line.kind === "ask") {
			void send({ action: "ask", anchor: line.anchor, question: text });
		} else {
			if (editable) editor.chain().focus().setMark("highlight", { color: "yellow" }).run();
			void send({ action: "note", anchor: line.anchor, text });
		}
		collapse();
		close();
	};

	if (!place) return null;
	if (line) {
		return (
			<div className={`piper-askline ${line.kind}`} style={{ left: place.left, top: place.top }}>
				<span className="star">{line.kind === "ask" ? "✳" : "✎"}</span>
				<input
					autoFocus
					value={input}
					placeholder={line.kind === "ask" ? "Ask about the selected text" : "Add a note to the selected text"}
					onChange={(event) => setInput(event.target.value)}
					onKeyDown={(event) => {
						if (event.key === "Escape") close();
						if (event.key === "Enter" && !event.nativeEvent.isComposing) submit();
					}}
				/>
				<kbd>↩</kbd>
			</div>
		);
	}
	return (
		<div
			ref={barRef}
			className="piper-selbar"
			style={{ left: place.left, top: place.top }}
			onMouseDown={(event) => event.preventDefault()}
		>
			{editable && (
				<button type="button" onClick={() => highlight("yellow")}>
					Highlight
				</button>
			)}
			<button type="button" onClick={() => act("note")}>Note</button>
			<span className="div" />
			<button type="button" onClick={() => act("ask")}>Ask</button>
			<button type="button" onClick={() => act("explain")}>Explain</button>
			<button type="button" onClick={() => act("define")}>Define</button>
			<button type="button" onClick={() => act("capture")}>Capture</button>
			{editable && (
				<>
					<span className="div" />
					<button type="button" className="fmt" title="Bold" onClick={() => editor.chain().focus().toggleBold().run()}>
						<b>B</b>
					</button>
					<button type="button" className="fmt" title="Italic" onClick={() => editor.chain().focus().toggleItalic().run()}>
						<i>I</i>
					</button>
					<button
						type="button"
						className="fmt"
						title="Link"
						onClick={() => {
							close();
							editor.commands.focus();
							editor.commands.toggleLinkAtSelection();
						}}
					>
						Link
					</button>
				</>
			)}
		</div>
	);
}

function MarginCards({
	editor,
	viewport,
	cards,
	wide,
}: {
	editor: Editor;
	viewport: HTMLDivElement;
	cards: PageNote[];
	wide: boolean;
}) {
	const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
	const slots = useRef(new Map<string, HTMLDivElement>());

	useEffect(() => {
		const expand = (event: MouseEvent) => {
			const mark = (event.target as HTMLElement).closest?.(".piper-question") as HTMLElement | null;
			const id = mark?.dataset.n;
			if (!id || !editor.state.selection.empty) return;
			setCollapsed((value) => {
				const next = new Set(value);
				next.delete(id);
				return next;
			});
		};
		const dom = editor.view.dom;
		dom.addEventListener("click", expand);
		return () => dom.removeEventListener("click", expand);
	}, [editor]);

	// Each card sits beside its passage, and never over the card above it.
	useLayoutEffect(() => {
		const place = () => {
			if (!wide) {
				for (const slot of slots.current.values()) slot.style.top = "";
				return;
			}
			const box = viewport.getBoundingClientRect();
			const wanted = cards.map((card) => {
				const range = findQuote(editor.state.doc, card);
				const y = range ? editor.view.coordsAtPos(range.from).top - box.top + viewport.scrollTop - 10 : Number.POSITIVE_INFINITY;
				return { id: card.id, y };
			});
			wanted.sort((a, b) => a.y - b.y);
			let floor = 0;
			for (const { id, y } of wanted) {
				const top = Math.max(Number.isFinite(y) ? y : floor, floor);
				const slot = slots.current.get(id);
				if (slot) slot.style.top = `${top}px`;
				floor = top + (slot?.offsetHeight ?? 80) + 12;
			}
		};
		place();
		editor.on("update", place);
		const observer = new ResizeObserver(place);
		observer.observe(viewport);
		return () => {
			editor.off("update", place);
			observer.disconnect();
		};
	}, [cards, wide, collapsed, editor, viewport]);

	if (cards.length === 0) return null;
	const toggle = (id: string, hide: boolean) =>
		setCollapsed((value) => {
			const next = new Set(value);
			if (hide) next.add(id);
			else next.delete(id);
			return next;
		});

	return (
		<div className={wide ? "piper-margin wide" : "piper-margin"}>
			{cards.map((card) => (
				<div
					key={card.id}
					ref={(element) => {
						if (element) slots.current.set(card.id, element);
						else slots.current.delete(card.id);
					}}
					className="piper-card-slot"
				>
					{card.kind === "note" ? (
						<MineCard card={card} />
					) : (
						<QuestionCard card={card} collapsed={collapsed.has(card.id)} toggle={(hide) => toggle(card.id, hide)} />
					)}
				</div>
			))}
		</div>
	);
}

function Paragraphs({ text }: { text: string }) {
	return (
		<>
			{text
				.split(/\n{2,}/)
				.filter((part) => part.trim())
				.map((part, index) => (
					<p key={index}>{inlineCode(part)}</p>
				))}
		</>
	);
}

function inlineCode(text: string): ReactNode[] {
	return text.split(/(`[^`]+`)/).map((part, index) =>
		part.startsWith("`") && part.endsWith("`") && part.length > 1 ? (
			<code key={index}>{part.slice(1, -1)}</code>
		) : (
			part
		),
	);
}

function MineCard({ card }: { card: PageNote }) {
	return (
		<div className="piper-card mine">
			<div className="ch">
				<b>Your note</b>
				<span className="when">{card.origin}</span>
			</div>
			<div className="quote">{card.quote.length > 90 ? `${card.quote.slice(0, 90)}…` : card.quote}</div>
			<Paragraphs text={card.comment} />
		</div>
	);
}

function QuestionCard({ card, collapsed, toggle }: { card: PageNote; collapsed: boolean; toggle: (hide: boolean) => void }) {
	const [follow, setFollow] = useState("");
	if (collapsed) {
		return (
			<button type="button" className="piper-card min" onClick={() => toggle(false)} aria-label={`Show ${card.label}`}>
				<span className="ch">
					<b>✳ {card.label}</b>
					<span>{card.quote.length > 28 ? `${card.quote.slice(0, 28)}…` : card.quote}</span>
				</span>
			</button>
		);
	}
	const turns = card.turns.length;
	return (
		<div className="piper-card">
			<div className="ch">
				<b>✳ {card.label}</b>
				<span>{card.agent || "Agent"}</span>
				<button type="button" className="x" title="Hide" aria-label="Hide" onClick={() => toggle(true)}>
					×
				</button>
			</div>
			<div className="quote">{card.quote.length > 90 ? `${card.quote.slice(0, 90)}…` : card.quote}</div>
			{card.turns.map((turn, index) => (
				<div key={index}>
					{turn.question ? <div className="q">{turn.question}</div> : null}
					{turn.answer ? (
						<Paragraphs text={turn.answer} />
					) : index === turns - 1 && card.pending ? (
						<p className="typing">
							<i />
							<i />
							<i />
						</p>
					) : null}
				</div>
			))}
			{card.tools && !card.pending ? <div className="tools">{card.tools}</div> : null}
			{card.failure ? <p className="failure">{card.failure}</p> : null}
			{!card.pending ? (
				<>
					<div className="acts">
						<button type="button" onClick={() => void send({ action: "open", id: card.id })}>Open Note</button>
						<button type="button" onClick={() => void send({ action: "copy", id: card.id })}>Copy</button>
						<button
							type="button"
							title="Open a session with this thread and the page, with every tool"
							onClick={() => void send({ action: "continue", id: card.id })}
						>
							Continue in Session
						</button>
						<span className="muted">#question{turns > 1 ? ` · ${turns} turns` : ""}</span>
					</div>
					<input
						className="follow"
						placeholder="Ask a follow-up"
						value={follow}
						onChange={(event) => setFollow(event.target.value)}
						onKeyDown={(event) => {
							if (event.key !== "Enter" || event.nativeEvent.isComposing || !follow.trim()) return;
							void send({ action: "followup", id: card.id, question: follow.trim() });
							setFollow("");
						}}
					/>
				</>
			) : null}
		</div>
	);
}
