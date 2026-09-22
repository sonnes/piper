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
    @State private var editingSection: String?
    @State private var sectionName = ""
    @State private var deletingSection: String?

    var body: some View {
        VStack(spacing: 0) {
            SidebarOutline(model: model, unreadCounts: model.unreadFolderCounts,
                           sections: sectionCounts,
                           sessionFolders: sessionFolders,
                           expanded: $expanded, selection: selection, select: select,
                           newSection: { namingSection = true },
                           editSection: { section in
                               sectionName = section
                               editingSection = section
                           },
                           deleteSection: { deletingSection = $0 })
            if !model.wikiProblems.isEmpty {
                DisclosureGroup("\(model.wikiProblems.count) file warnings") {
                    Text(model.wikiProblems.joined(separator: "\n"))
                        .textSelection(.enabled).font(PiperTheme.ui(10)).padding(.top, 5)
                }
                .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.warning)
                .padding(.horizontal, AppDefaults.Sidebar.rowInset).padding(.vertical, 6)
            }
        }
        .sheet(isPresented: $namingSection) {
            NewSectionSheet(sections: model.store.sections) { name in
                guard model.store.chooseSection(name) else { return }
                namingSection = false
                expanded.remove(SidebarOutline.inboxCollapsedKey)
                select(.section(model.store.activeSection))
            }
        }
        .alert("Edit Section", isPresented: Binding(
            get: { editingSection != nil },
            set: { if !$0 { editingSection = nil } }
        ), presenting: editingSection) { section in
            TextField("Name", text: $sectionName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                guard model.store.renameSection(section, to: sectionName) else { return }
                if selection == .section(section) {
                    select(.section(sectionName.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            .disabled(sectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .alert("Delete Section?", isPresented: Binding(
            get: { deletingSection != nil },
            set: { if !$0 { deletingSection = nil } }
        ), presenting: deletingSection) { section in
            Button("Cancel", role: .cancel) {}
            Button("Delete Section", role: .destructive) {
                guard model.store.deleteSection(section) else { return }
                if selection == .section(section) { select(.inbox) }
            }
        } message: { section in
            Text("Delete \"\(section)\" and move its notes to Inbox. You can undo this change.")
        }
        .onChange(of: model.store.sections) { _, sections in
            if case .section(let name) = selection, !sections.contains(name) { select(.inbox) }
        }
    }

    /// Every capture section and the number of notes that are not done.
    private var sectionCounts: [SidebarSection] {
        model.store.sections.map { section in
            SidebarSection(name: section, count: model.store.notes.filter { $0.section == section && !$0.isDone }.count)
        }
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
