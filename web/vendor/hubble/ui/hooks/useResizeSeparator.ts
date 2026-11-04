import {
	type KeyboardEvent as ReactKeyboardEvent,
	type PointerEvent as ReactPointerEvent,
	type RefObject,
	useRef,
	useState,
} from "react";

export type ResizeAxis = "col" | "row";

export type ResizePointerContext<TElement extends HTMLElement> = {
	event: ReactPointerEvent<TElement>;
	startRect: DOMRect | null;
};

type ResizeOrientation = "horizontal" | "vertical";

type ResizeSeparatorOptions<TElement extends HTMLElement> = {
	axis: ResizeAxis;
	label: string;
	value: number;
	min: number;
	max: number | (() => number);
	step?: number;
	onChange: (value: number) => void;
	getPointerValue: (context: ResizePointerContext<TElement>) => number | null;
	onResizeStart?: () => void;
	onResizeEnd?: () => void;
	onCommit?: () => void;
	targetRef?: RefObject<HTMLElement | null>;
};

function resolveValue(value: number | (() => number)) {
	return typeof value === "function" ? value() : value;
}

function clamp(value: number, min: number, max: number) {
	return Math.max(min, Math.min(max, value));
}

export function useResizeSeparator<
	TElement extends HTMLElement = HTMLDivElement,
>({
	axis,
	label,
	value,
	min,
	max,
	step = 16,
	onChange,
	getPointerValue,
	onResizeStart,
	onResizeEnd,
	onCommit,
	targetRef,
}: ResizeSeparatorOptions<TElement>) {
	const pointerIdRef = useRef<number | null>(null);
	const startRectRef = useRef<DOMRect | null>(null);
	const [isResizing, setIsResizing] = useState(false);

	const maxValue = resolveValue(max);
	const orientation: ResizeOrientation =
		axis === "col" ? "vertical" : "horizontal";

	function commit(nextValue: number) {
		onChange(clamp(nextValue, min, resolveValue(max)));
	}

	function finishResize(event: ReactPointerEvent<TElement>) {
		const pointerId = pointerIdRef.current;
		if (pointerId !== event.pointerId) return;
		if (event.currentTarget.hasPointerCapture(pointerId)) {
			event.currentTarget.releasePointerCapture(pointerId);
		}
		pointerIdRef.current = null;
		setIsResizing(false);
		onCommit?.();
		onResizeEnd?.();
	}

	function onKeyDown(event: ReactKeyboardEvent<TElement>) {
		let nextValue: number | null = null;
		if (axis === "col") {
			if (event.key === "ArrowLeft") {
				nextValue = value - step;
			} else if (event.key === "ArrowRight") {
				nextValue = value + step;
			}
		} else if (event.key === "ArrowUp") {
			nextValue = value + step;
		} else if (event.key === "ArrowDown") {
			nextValue = value - step;
		}
		if (event.key === "Home") {
			nextValue = min;
		} else if (event.key === "End") {
			nextValue = resolveValue(max);
		}
		if (nextValue === null) return;
		event.preventDefault();
		commit(nextValue);
		onCommit?.();
	}

	function onPointerDown(event: ReactPointerEvent<TElement>) {
		event.preventDefault();
		pointerIdRef.current = event.pointerId;
		startRectRef.current = targetRef?.current?.getBoundingClientRect() ?? null;
		event.currentTarget.setPointerCapture(event.pointerId);
		setIsResizing(true);
		onResizeStart?.();
	}

	function onPointerMove(event: ReactPointerEvent<TElement>) {
		if (pointerIdRef.current !== event.pointerId) return;
		event.preventDefault();
		const nextValue = getPointerValue({
			event,
			startRect: startRectRef.current,
		});
		if (nextValue === null) return;
		commit(nextValue);
	}

	return {
		isResizing,
		separatorProps: {
			"aria-label": label,
			"aria-orientation": orientation,
			"aria-valuemax": maxValue,
			"aria-valuemin": min,
			"aria-valuenow": Math.round(value),
			onKeyDown,
			onPointerCancel: finishResize,
			onPointerDown,
			onPointerMove,
			onPointerUp: finishResize,
			role: "separator",
			tabIndex: 0,
		},
	};
}
