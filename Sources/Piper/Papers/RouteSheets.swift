import SwiftUI

/// The error alert that a paper presents.
///
/// The modifier goes on the feed paper only, so the alert cannot open twice.
struct RouteSheets: ViewModifier {

    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            .alert("Piper", isPresented: Binding(
                get: { model.store.errorMessage != nil },
                set: { if !$0 { model.store.errorMessage = nil } }
            )) {
                Button("OK") { model.store.errorMessage = nil }
            } message: {
                Text(model.store.errorMessage ?? "")
            }
    }
}

extension View {
    /// Presents the error alert.
    func routeSheets(_ model: AppModel) -> some View {
        modifier(RouteSheets(model: model))
    }
}
