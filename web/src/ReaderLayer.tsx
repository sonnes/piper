// The selection bar and the margin cards of the Reader tab, in the editor.
// Ported from Sources/Piper/Resources/reader.html. A highlight goes into the
// file. A note, a question, and an answer are notes in Piper, which the margin
// cards show.

import { Extension } from "@tiptap/core";
import type { Node as PMNode } from "@tiptap/pm/model";
import { Plugin, PluginKey } from "@tiptap/pm/state";
import { Decoration, DecorationSet } from "@tiptap/pm/view";
import type { Editor } from "@tiptap/react";
import { type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { send } from "./bridge";

/** A margin note from Piper. The fields match `ReaderPageNote` in Swift. */
export type PageNote = {
	id: string;
	kind: "highlight" | "note" | "question";
	color: string;
	quote: string;
	comment: string;
	origin: string;
	label: string;
	turns: { question: string | null; answer: string }[];
	pending: boolean;
	failure: string | null;
	agent: string;
	tools: string;
};

type Anchor = { quote: string; block: number; offset: number };

const CARD_WIDTH = 250;
const CARD_GAP = 36;
const COLUMN = 736;
const COLORS = ["yellow", "green", "pink"] as const;

// ---------- the place of a quote ----------

/** The document range of the first occurrence of a quote, or null. */
export function findQuote(doc: PMNode, quote: string): { from: number; to: number } | null {
	if (!quote) return null;
	let found: { from: number; to: number } | null = null;
	doc.forEach((block, blockPos) => {
		if (found) return;
		const parts: { pos: number; text: string }[] = [];
		block.descendants((node, pos) => {
			if (node.isText && node.text) parts.push({ pos: blockPos + 1 + pos, text: node.text });
		});
		const text = parts.map((part) => part.text).join("");
		const at = text.indexOf(quote);
		if (at < 0) return;
		const position = (offset: number) => {
			let rest = offset;
			for (const part of parts) {
				if (rest <= part.text.length) return part.pos + rest;
				rest -= part.text.length;
			}
			return parts.at(-1) ? (parts.at(-1)?.pos ?? 0) + (parts.at(-1)?.text.length ?? 0) : blockPos;
		};
		found = { from: position(at), to: position(at + quote.length) };
	});
	return found;
}

/** The quote, the top-level block, and the offset of the selection, clipped to its first block. */
function selectedAnchor(editor: Editor): Anchor | null {
	const { from, to, empty } = editor.state.selection;
	if (empty) return null;
	const doc = editor.state.doc;
	const $from = doc.resolve(from);
	if ($from.depth < 1) return null;
	const start = $from.start(1);
	const end = Math.min(to, $from.end(1));
	const raw = doc.textBetween(from, end, " ");
	const quote = raw.trim();
	if (!quote) return null;
	const offset = doc.textBetween(start, from, " ").length + (raw.length - raw.trimStart().length);
	return { quote, block: $from.index(0), offset };
}

// ---------- the underline of a question ----------

const questionKey = new PluginKey<DecorationSet>("piperQuestions");
let questions: PageNote[] = [];

function decorations(doc: PMNode) {
	const items = questions.flatMap((note) => {
		const range = findQuote(doc, note.quote);
		return range ? [Decoration.inline(range.from, range.to, { class: "piper-question", "data-n": note.id })] : [];
	});
	return DecorationSet.create(doc, items);
}

/** Underlines the passage of each question. */
export const QuestionMarks = Extension.create({
	name: "piperQuestions",
	addProseMirrorPlugins() {
		return [
			new Plugin<DecorationSet>({
				key: questionKey,
				state: {
					init: (_, state) => decorations(state.doc),
					apply: (tr, value) =>
						tr.docChanged || tr.getMeta(questionKey) ? decorations(tr.doc) : value,
				},
				props: { decorations: (state) => questionKey.getState(state) },
			}),
		];
	},
});

function setQuestions(editor: Editor | null, notes: PageNote[]) {
	questions = notes.filter((note) => note.kind === "question");
	if (editor && !editor.isDestroyed) editor.view.dispatch(editor.state.tr.setMeta(questionKey, true));
}

// ---------- the layer ----------

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

	useEffect(() => setQuestions(editor, notes), [editor, notes]);

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

// ---------- the selection bar ----------

type Line = { kind: "ask" | "note"; anchor: Anchor } | null;

function SelectionBar({ editor, viewport, editable }: { editor: Editor; viewport: HTMLDivElement; editable: boolean }) {
	const [place, setPlace] = useState<{ left: number; top: number } | null>(null);
	const [line, setLine] = useState<Line>(null);
	const [input, setInput] = useState("");
	const barRef = useRef<HTMLDivElement | null>(null);

	useEffect(() => {
		const show = () => {
			window.setTimeout(() => {
				if (editor.isDestroyed || !selectedAnchor(editor)) {
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
		const anchor = selectedAnchor(editor);
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
					// biome-ignore lint/a11y/noAutofocus: the line opens for typing
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
			<button type="button" className="ask" onClick={() => act("ask")}>✳ Ask</button>
			<button type="button" onClick={() => act("explain")}>Explain</button>
			<button type="button" onClick={() => act("define")}>Define</button>
			<span className="div" />
			{editable &&
				COLORS.map((color) => (
					<button
						key={color}
						type="button"
						className={`sw ${color}`}
						title={color[0].toUpperCase() + color.slice(1)}
						aria-label={`Highlight ${color}`}
						onClick={() => highlight(color)}
					/>
				))}
			{editable && <span className="div" />}
			<button type="button" onClick={() => act("note")}>Note</button>
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
							(editor.commands as unknown as { toggleLinkAtSelection: () => boolean }).toggleLinkAtSelection();
						}}
					>
						Link
					</button>
				</>
			)}
		</div>
	);
}

// ---------- the margin cards ----------

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
	const [tops, setTops] = useState<Record<string, number>>({});
	const refs = useRef(new Map<string, HTMLDivElement>());
	const [version, setVersion] = useState(0);

	useEffect(() => {
		const bump = () => setVersion((value) => value + 1);
		editor.on("update", bump);
		const observer = new ResizeObserver(bump);
		observer.observe(viewport);
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
		return () => {
			editor.off("update", bump);
			observer.disconnect();
			dom.removeEventListener("click", expand);
		};
	}, [editor, viewport]);

	// Each card sits beside its passage, and never over the card above it.
	// biome-ignore lint/correctness/useExhaustiveDependencies: version and collapsed change the layout
	useLayoutEffect(() => {
		if (!wide) return;
		const box = viewport.getBoundingClientRect();
		const wanted = cards.map((card) => {
			const range = findQuote(editor.state.doc, card.quote);
			const y = range ? editor.view.coordsAtPos(range.from).top - box.top + viewport.scrollTop - 10 : Number.POSITIVE_INFINITY;
			return { id: card.id, y };
		});
		wanted.sort((a, b) => a.y - b.y);
		let floor = 0;
		const next: Record<string, number> = {};
		for (const { id, y } of wanted) {
			const top = Math.max(Number.isFinite(y) ? y : floor, floor);
			next[id] = top;
			floor = top + (refs.current.get(id)?.offsetHeight ?? 80) + 12;
		}
		setTops(next);
	}, [cards, wide, version, collapsed, editor, viewport]);

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
						if (element) refs.current.set(card.id, element);
						else refs.current.delete(card.id);
					}}
					style={wide ? { top: tops[card.id] ?? 0 } : undefined}
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
					// biome-ignore lint/suspicious/noArrayIndexKey: the paragraphs have no id
					<p key={index}>{inlineCode(part)}</p>
				))}
		</>
	);
}

function inlineCode(text: string): ReactNode[] {
	return text.split(/(`[^`]+`)/).map((part, index) =>
		part.startsWith("`") && part.endsWith("`") && part.length > 1 ? (
			// biome-ignore lint/suspicious/noArrayIndexKey: the parts have no id
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
				// biome-ignore lint/suspicious/noArrayIndexKey: the turns have no id
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
