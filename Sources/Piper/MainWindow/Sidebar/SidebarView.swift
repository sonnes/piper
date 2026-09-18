import AppKit
import PiperTree
import SwiftUI
import Vault

/// The source list, its actions, and file warnings.
struct SidebarView: View {
    @Bindable var model: AppModel
    @Binding var expanded: Set<String>
    let selection: SidebarSelection
    let select: (SidebarSelection) -> Void
    @State private var namingSection = false

    var body: some View {
        VStack(spacing: 0) {
            SidebarOutline(model: model, unreadCounts: model.unreadFolderCounts,
                           sections: sectionCounts,
                           sessionFolders: sessionFolders,
                           expanded: $expanded, selection: selection, select: select,
                           newSection: { namingSection = true })
            if !model.wikiProblems.isEmpty {
                DisclosureGroup("\(model.wikiProblems.count) file warnings") {
                    Text(model.wikiProblems.joined(separator: "\n"))
                        .textSelection(.enabled).font(PiperTheme.ui(10)).padding(.top, 5)
                }
                .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.warning)
                .padding(.horizontal, AppDefaults.Sidebar.rowInset).padding(.vertical, 6)
            }
            HStack(spacing: 14) {
                footerButton("New Section") { namingSection = true }
                footerButton("Add Folder…") { model.chooseWiki() }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppDefaults.Sidebar.rowInset)
            .frame(height: 32)
        }
        .sheet(isPresented: $namingSection) {
            NewSectionSheet(sections: model.store.sections) { name in
                guard model.store.chooseSection(name) else { return }
                namingSection = false
                expanded.remove(SidebarOutline.inboxCollapsedKey)
                select(.section(model.store.activeSection))
            }
        }
    }

    /// Every capture section and the number of notes that are not done.
    private var sectionCounts: [SidebarSection] {
        model.store.sections.map { section in
            SidebarSection(name: section, count: model.store.notes.filter { $0.section == section && !$0.isDone }.count)
        }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "plus")
                .labelStyle(SidebarFooterLabelStyle())
        }
        .buttonStyle(.plain)
        .help(title)
    }

    /// The folders with Claude sessions, and the sessions in each that need the reader.
    private var sessionFolders: [SidebarSessionFolder] {
        let runner = model.agents.runner
        return runner.folders().map { folder in
            SidebarSessionFolder(path: folder, attention: runner.sessions(in: folder).filter { $0.state == .needsYou }.count)
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

/// One folder in the Claude group of the sidebar.
struct SidebarSessionFolder: Equatable {
    let path: String
    /// The sessions that wait for an answer.
    let attention: Int
}

/// One capture section in the sidebar.
struct SidebarSection: Equatable {
    let name: String
    let count: Int
}

private struct SidebarFooterLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.icon.font(.system(size: 11, weight: .medium))
            configuration.title.font(PiperTheme.ui(12))
        }
        .foregroundStyle(PiperTheme.secondary)
        .contentShape(Rectangle())
    }
}
