import SwiftUI

/// The error alert that the main window presents.
///
/// The modifier goes on the home page and on the detail pane. Only one of those
/// is in the view hierarchy at a time, so the alert cannot open twice.
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
