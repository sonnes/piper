/** The anchor of a heading. It matches `WikiMarkdown.anchor` in Piper. */
export function anchor(text: string): string {
	return text
		.toLowerCase()
		.replace(/[^\p{L}\p{N} _-]/gu, "")
		.trim()
		.replace(/ +/g, "-");
}

/** Scrolls to the first heading whose anchor matches. Returns false if no heading matches. */
export function scrollToAnchor(root: ParentNode, requested: string): boolean {
	const wanted = [requested, anchor(requested)];
	const headings = root.querySelectorAll<HTMLElement>(
		".ProseMirror :is(h1, h2, h3, h4, h5, h6)",
	);
	const anchors = headingAnchors([...headings].map((heading) => heading.textContent ?? ""));
	const index = anchors.findIndex((value) => wanted.includes(value));
	if (index < 0) return false;
	headings[index]?.scrollIntoView({ block: "start" });
	return true;
}

/** The anchor of each heading. A repeated heading gets `-1`, `-2`, and more, as in Piper. */
export function headingAnchors(titles: string[]): string[] {
	const counts = new Map<string, number>();
	return titles.map((title) => {
		const slug = anchor(title);
		const count = counts.get(slug) ?? 0;
		counts.set(slug, count + 1);
		return count === 0 ? slug : `${slug}-${count}`;
	});
}
