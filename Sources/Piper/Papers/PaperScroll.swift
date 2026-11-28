import AppKit

/// Scrolls the scroll view of a reader paper with the keyboard, for a paper
/// without a reader page, such as the comments of a Hacker News story.
enum PaperScroll {

    /// The scroll view that the keys move: the largest visible scroll view
    /// in the view whose document is taller than the scroll view.
    @MainActor static func scrollView(in root: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        func visit(_ view: NSView) {
            if view.isHiddenOrHasHiddenAncestor { return }
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.frame.height > scroll.contentView.bounds.height {
                found.append(scroll)
            }
            view.subviews.forEach(visit)
        }
        visit(root)
        return found.max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
    }

    /// Moves the scroll view down by `delta` points, or up for a negative delta.
    @MainActor static func scroll(_ scrollView: NSScrollView, by delta: CGFloat, animate: Bool) {
        guard let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        // A flipped document grows down, so a move down adds to y.
        let down = document.isFlipped ? delta : -delta
        var origin = clip.bounds.origin
        origin.y = offset(origin.y, by: down, content: document.frame.height, visible: clip.bounds.height)
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Metrics.duration
                clip.animator().setBoundsOrigin(origin)
            }
        } else {
            clip.setBoundsOrigin(origin)
        }
        scrollView.reflectScrolledClipView(clip)
    }

    /// Moves the scroll view one screen down for 1, or up for -1, less a few lines that stay in view.
    @MainActor static func page(_ scrollView: NSScrollView, by direction: CGFloat, animate: Bool) {
        scroll(scrollView, by: direction * pageHeight(visible: scrollView.contentView.bounds.height), animate: animate)
    }

    /// The scroll offset after a move, kept between the top and the bottom of the content.
    static func offset(_ current: CGFloat, by delta: CGFloat, content: CGFloat, visible: CGFloat) -> CGFloat {
        min(max(current + delta, 0), max(content - visible, 0))
    }

    /// The move of one page: most of the visible height, so the last lines stay in view.
    static func pageHeight(visible: CGFloat) -> CGFloat {
        (visible * Metrics.pageFraction).rounded()
    }
}

extension PaperScroll {
    enum Metrics {
        /// The part of the visible height that Page Up and Page Down move, as in the Reader tab.
        static let pageFraction: CGFloat = 0.85
        static let duration: TimeInterval = 0.15
    }
}
