/// The one way for a part of the model to open a paper.
///
/// `AppModel` makes it before the desk exists and gives its `open(_:)` to
/// each part. `PaperDesk` sets `handler` when the app makes the desk.
@MainActor
final class PaperOpener {
    var handler: (PaperItem) -> Void = { _ in }

    func open(_ item: PaperItem) {
        handler(item)
    }
}
