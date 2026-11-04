export function isEditableEventTarget(target: EventTarget | null) {
	if (!(target instanceof HTMLElement)) return false;
	if (target.isContentEditable) return true;
	return Boolean(
		target.closest("input, textarea, select, [contenteditable=true]"),
	);
}
