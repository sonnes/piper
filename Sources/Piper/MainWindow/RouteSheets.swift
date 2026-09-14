import SwiftUI

/// The sheets and the alert that the main window presents.
///
/// `AppModel.route` names what the window shows. The modifier goes on the home
/// page and on the detail pane. Only one of those is in the view hierarchy at a
/// time, so a sheet cannot open twice.
struct RouteSheets: ViewModifier {

    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: route("settings")) { SettingsView(model: model) }
            .sheet(isPresented: route("commands")) { WikiCommandView(model: model) }
            .alert("Piper", isPresented: Binding(
                get: { model.store.errorMessage != nil },
                set: { if !$0 { model.store.errorMessage = nil } }
            )) {
                Button("OK") { model.store.errorMessage = nil }
            } message: {
                Text(model.store.errorMessage ?? "")
            }
    }

    private func route(_ name: String) -> Binding<Bool> {
        Binding(get: { model.route == name }, set: { if !$0 { model.route = "wiki" } })
    }
}

extension View {
    /// Presents Settings, Commands And Skills, and the error alert.
    func routeSheets(_ model: AppModel) -> some View {
        modifier(RouteSheets(model: model))
    }
}
