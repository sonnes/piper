import AppKit
import SwiftUI
import Vault

/// The detail pane when nothing is selected.
struct NoSelection: View {
    var body: some View {
        EmptyPane(title: "No Selection")
            .background(PiperTheme.page)
    }
}
