import AppKit
import PiperTree
import SwiftUI
import Vault

/// The source list and file warnings of the main window.
struct SidebarView: View {
    @Bindable var model: AppModel
    @Binding var expanded: Set<String>
    let selection: SidebarSelection
    let select: (SidebarSelection) -> Void

    var body: some View {
        VStack(spacing: 0) {
            SidebarOutline(model: model, unreadCounts: model.unreadFolderCounts,
                           expanded: $expanded, selection: selection, select: select)
            if !model.wikiProblems.isEmpty {
                DisclosureGroup("\(model.wikiProblems.count) file warnings") {
                    Text(model.wikiProblems.joined(separator: "\n"))
                        .textSelection(.enabled).font(PiperTheme.ui(10)).padding(.top, 5)
                }.font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.warning).padding(12)
            }
        }
    }

    /// Every folder path in the files, at every level.
    static func folders(of files: [VaultFile], including empty: [String] = []) -> Set<String> {
        var result = Set(empty)
        for document in files {
            var folder = document.folder
            while !folder.isEmpty {
                result.insert(folder)
                folder = (folder as NSString).deletingLastPathComponent
            }
        }
        return result
    }
}
