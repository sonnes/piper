import AppKit
import SwiftUI

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var showSidebar = true
    @AppStorage("wikiInspectorVisible") private var showInspector = true
    @State private var focused = false
    @State private var expanded: Set<String> = []
    @State private var initializedTree = false
    @State private var monitor: Any?
    @State private var window: NSWindow?
    @State private var showReading = false
    @AppStorage("wikiReaderSize") private var readerSize = 18.0
    @AppStorage("wikiReaderTheme") private var readerTheme = WikiReadingTheme.paper
    @AppStorage("wikiReaderFont") private var readerFont = WikiReadingFont.mono
    @AppStorage("wikiReaderAppearance") private var readerAppearance = WikiReadingAppearance.system
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !focused { ribbon; Rule(vertical: true) }
                if showSidebar && !focused { sidebar.frame(width: 230); Rule(vertical: true) }
                VStack(spacing: 0) {
                    if !focused {
                        tabStrip
                        Rule()
                        if let document = model.currentDocument { crumbs(document) }
                    }
                    workspace
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if showInspector && !focused, let document = model.currentDocument {
                    Rule(vertical: true)
                    WikiInspector(model: model, document: document, focus: { focused = true })
                        .frame(width: 250)
                }
            }
            Rule()
            statusBar
        }
        .id(model.style)
        .background(PiperTheme.page)
        .foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.accent)
        .accentColor(PiperTheme.accent)
        .preferredColorScheme(readerAppearance.colorScheme)
        .frame(minWidth: 850, minHeight: 600)
        .background(WindowReference { window = $0; $0?.isDocumentEdited = model.wikiEdit?.hasChanges == true })
        .sheet(isPresented: Binding(get: { model.route == "settings" }, set: { if !$0 { model.route = "wiki" } })) {
            SettingsView(model: model)
        }
        .alert("Piper", isPresented: Binding(get: { model.store.errorMessage != nil }, set: { if !$0 { model.store.errorMessage = nil } })) {
            Button("OK") { model.store.errorMessage = nil }
        } message: { Text(model.store.errorMessage ?? "") }
        .onAppear { expandInitialFolders(); installKeys() }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        .onChange(of: model.documents.map(\.id)) { _, _ in expandInitialFolders() }
        .onChange(of: model.wikiPath) { _, _ in initializedTree = false; expanded = []; expandInitialFolders() }
        .onChange(of: model.wikiEdit?.hasChanges) { _, changed in window?.isDocumentEdited = changed == true }
        .onChange(of: model.selectedDocument) { _, path in
            guard let path else { return }
            var folder = (path as NSString).deletingLastPathComponent
            while !folder.isEmpty { expanded.insert(folder); folder = (folder as NSString).deletingLastPathComponent }
        }
    }

    // MARK: Ribbon and sidebar

    private var ribbon: some View {
        VStack(spacing: 6) {
            IconButton(title: "Files", icon: "doc.text", active: showSidebar) { showSidebar.toggle() }
            IconButton(title: "Search Wiki · ⌘O", icon: "magnifyingglass") { focusSearch() }
            IconButton(title: "Open Capture Panel · ⌘1", icon: "square.and.pencil") { model.openPanel?() }
            Spacer()
            IconButton(title: "Settings · ⌘,", icon: "gearshape") { model.route = "settings" }
        }
        .padding(.top, 48).padding(.bottom, 10)
        .frame(width: 42)
        .background(PiperTheme.surface)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Text(model.wikiQuery.isEmpty ? "FILES" : "\(model.filteredDocuments.count) RESULTS")
                    .font(PiperTheme.ui(10.5, weight: .semibold)).tracking(0.4).foregroundStyle(PiperTheme.secondary)
                Spacer()
                if model.wikiQuery.isEmpty {
                    IconButton(title: expanded.isEmpty ? "Expand Folders" : "Collapse Folders", icon: "list.bullet.indent") {
                        expanded = expanded.isEmpty ? allFolders : []
                    }
                }
                IconButton(title: "Refresh Wiki · ⌘R", icon: "arrow.clockwise") { model.reload() }.disabled(model.loading)
            }
            .padding(.leading, 14).padding(.trailing, 6).frame(height: 30).padding(.top, 44)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(PiperTheme.secondary)
                TextField("Search", text: $model.wikiQuery).textFieldStyle(.plain).font(PiperTheme.ui(12))
                    .focused($searching).accessibilityLabel("Search Wiki")
                    .onSubmit { if let first = model.filteredDocuments.first { model.openDocument(first.id) } }
                if !model.wikiQuery.isEmpty {
                    Button { model.wikiQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear Wiki Search")
                } else { Text("⌘O").font(PiperTheme.ui(10)).foregroundStyle(PiperTheme.faint) }
            }
            .padding(.horizontal, 8).frame(height: 28)
            .overlay(alignment: .bottom) { Rectangle().fill(searching ? PiperTheme.accent : PiperTheme.rule).frame(height: 1) }
            .padding(.horizontal, 12).padding(.bottom, 8)
            ScrollView {
                if model.wikiQuery.isEmpty {
                    WikiTreeRows(nodes: WikiTreeNode.build(model.documents), expanded: $expanded, model: model)
                        .padding(.horizontal, 8)
                } else if model.filteredDocuments.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No matching notes").font(PiperTheme.ui(12, weight: .medium))
                        Text("Try a title, phrase, or folder name.").font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(model.filteredDocuments) { document in
                            let selected = model.selectedDocument == document.id
                            Button { model.openDocument(document.id) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(document.title).font(PiperTheme.ui(12, weight: .medium)).lineLimit(2)
                                    Text(searchExcerpt(document)).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary).lineLimit(3)
                                    Text(document.folder.isEmpty ? "Wiki" : document.folder).font(PiperTheme.ui(10)).foregroundStyle(PiperTheme.faint)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                    .background(selected ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 8)
                }
            }.scrollIndicators(.automatic)
            if !model.wikiProblems.isEmpty {
                DisclosureGroup("\(model.wikiProblems.count) file warnings") {
                    Text(model.wikiProblems.joined(separator: "\n")).textSelection(.enabled).font(PiperTheme.ui(10)).padding(.top, 5)
                }.font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.warning).padding(12)
            }
            Rule()
            HStack(spacing: 9) {
                Image(systemName: "externaldrive").font(.system(size: 14)).foregroundStyle(PiperTheme.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.repository.root.lastPathComponent).font(PiperTheme.ui(12, weight: .medium)).lineLimit(1)
                    Text((model.wikiPath as NSString).abbreviatingWithTildeInPath).font(PiperTheme.ui(10.5)).foregroundStyle(PiperTheme.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Menu {
                    Button("Choose Wiki Folder…") { model.chooseWiki() }
                    Button("Reveal Wiki in Finder") { NSWorkspace.shared.open(model.repository.root) }
                    Divider()
                    Button("Settings…") { model.route = "settings" }
                } label: { Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(PiperTheme.secondary) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Wiki Folder Options")
            }.padding(.horizontal, 14).frame(height: 52)
        }.background(PiperTheme.surface)
    }

    // MARK: Tab strip, crumbs, status

    private var tabStrip: some View {
        HStack(spacing: 4) {
            if !showSidebar { Color.clear.frame(width: 28, height: 1) }
            if let document = model.currentDocument {
                HStack(spacing: 8) {
                    if model.wikiEdit?.hasChanges == true { Circle().fill(PiperTheme.accent).frame(width: 6, height: 6) }
                    Text(document.title).font(PiperTheme.ui(12, weight: .medium)).lineLimit(1)
                }
                .padding(.horizontal, 16).frame(height: 38)
                .background(PiperTheme.page)
                .overlay(alignment: .trailing) { Rule(vertical: true) }
                .help(document.id)
            } else {
                Text("Wiki").font(PiperTheme.ui(12, weight: .medium)).foregroundStyle(PiperTheme.secondary).padding(.horizontal, 16)
            }
            Spacer(minLength: 0)
            IconButton(title: "Back · ⌘[", icon: "chevron.left") { model.navigate(-1) }.disabled(!model.workspace.canGoBack)
            IconButton(title: "Forward · ⌘]", icon: "chevron.right") { model.navigate(1) }.disabled(!model.workspace.canGoForward)
            Button { showReading.toggle() } label: {
                Text("Aa").font(PiperTheme.ui(11, weight: .medium)).foregroundStyle(showReading ? PiperTheme.ink : PiperTheme.secondary)
                    .frame(width: 30, height: 26).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Reading Preferences").accessibilityLabel("Reading Preferences")
                .popover(isPresented: $showReading, arrowEdge: .bottom) {
                    ReadingPreferencesView().padding(16).frame(width: 300)
                }
            if model.currentDocument != nil {
                IconButton(title: "Document Sidebar", icon: "sidebar.right", active: showInspector) { showInspector.toggle() }
            }
        }
        .padding(.trailing, 8).frame(height: 38)
        .background(PiperTheme.surface)
    }

    private func crumbs(_ document: WikiDocument) -> some View {
        HStack(spacing: 5) {
            Text("Wiki")
            ForEach(Array(document.id.split(separator: "/").enumerated()), id: \.offset) { _, part in
                Text("›").foregroundStyle(PiperTheme.faint)
                Text(String(part)).lineLimit(1)
            }
            Spacer()
        }
        .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
        .padding(.horizontal, 18).frame(height: 28)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("Local Wiki")
            Text("\(model.documents.count) files")
            Spacer()
            if focused {
                Text("Focus")
                Text("Esc to exit")
            } else if let document = model.currentDocument {
                let words = (model.wikiEdit?.markdown ?? document.body).split { $0.isWhitespace || $0.isNewline }.count
                Text("\(words.formatted()) words")
                if let edit = model.wikiEdit { Text(edit.hasChanges ? "Unsaved" : "Saved") }
            }
        }
        .font(PiperTheme.ui(10.5)).foregroundStyle(PiperTheme.secondary)
        .padding(.horizontal, 12).frame(height: 24)
        .background(PiperTheme.surface)
    }

    // MARK: Workspace

    private var workspace: some View {
        VStack(spacing: 0) {
            if let error = model.wikiError {
                ContentUnavailableView {
                    Label("Wiki Unavailable", systemImage: "folder.badge.questionmark")
                } description: { Text(error) } actions: {
                    Button("Create Wiki Here") { model.createWiki() }.buttonStyle(PiperButtonStyle(prominent: true))
                    Button("Choose Wiki Folder") { model.chooseWiki() }.buttonStyle(PiperButtonStyle())
                    Button("Retry") { model.reload() }.buttonStyle(PiperButtonStyle())
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let document = model.currentDocument {
                WikiEditor(model: model, document: document, fontSize: readerSize,
                           fontName: readerFont.font(size: readerSize).fontName, paper: readingPaper)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.loading {
                ProgressView("Opening Wiki…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(model.documents.isEmpty ? "Your Wiki Starts Here" : "Open a Note", systemImage: "book.closed")
                } description: {
                    Text(model.documents.isEmpty ? "Add Markdown files to this folder, or send captures to your Wiki." : "Choose a file from the sidebar, or search your Wiki.")
                } actions: {
                    if model.documents.isEmpty {
                        Button("Create Wiki") { model.createWiki() }.buttonStyle(PiperButtonStyle(prominent: true))
                        Button("Open Capture Panel") { model.openPanel?() }.buttonStyle(PiperButtonStyle())
                    }
                    else { Button("Search Wiki") { focusSearch() }.buttonStyle(PiperButtonStyle()) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var readingPaper: Color { Color(nsColor: readerTheme.background(dark: (readerAppearance.colorScheme ?? colorScheme) == .dark)) }

    private var allFolders: Set<String> {
        var result: Set<String> = []
        for document in model.documents {
            var folder = document.folder
            while !folder.isEmpty { result.insert(folder); folder = (folder as NSString).deletingLastPathComponent }
        }
        return result
    }

    private func expandInitialFolders() {
        guard !initializedTree, !model.documents.isEmpty else { return }
        expanded = allFolders
        initializedTree = true
    }

    private func searchExcerpt(_ document: WikiDocument) -> String {
        let text = document.body.replacingOccurrences(of: "\n", with: " ")
        let query = model.wikiQuery.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: query, options: .caseInsensitive) {
            let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
            return (start == text.startIndex ? "" : "…") + String(text[start...].prefix(150))
        }
        return document.description.isEmpty ? String(text.prefix(130)) : document.description
    }

    private func focusSearch() { focused = false; showSidebar = true; model.route = "wiki"; searching = true }

    private func installKeys() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === window, window?.attachedSheet == nil else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if modifiers == [.command, .option], key == "f" { focused.toggle(); return nil }
            if modifiers == .command {
                switch key {
                case "f":
                    if model.wikiEdit != nil { return event }
                    focusSearch(); return nil
                case "o": focusSearch(); return nil
                case "r": model.reload(); return nil
                case "[": model.navigate(-1); return nil
                case "]": model.navigate(1); return nil
                case "s": model.saveWikiEdit(); return nil
                case "w": window?.performClose(nil); return nil
                default: break
                }
            }
            if event.keyCode == 53 {
                if focused { focused = false; return nil }
                if searching { model.wikiQuery = ""; searching = false; return nil }
            }
            return event
        }
    }
}

private struct WikiTreeRows: View {
    let nodes: [WikiTreeNode]
    @Binding var expanded: Set<String>
    let model: AppModel
    var depth = 0

    var body: some View {
        VStack(spacing: 1) {
            ForEach(nodes) { node in
                let selected = !node.isFolder && model.selectedDocument == node.id
                let open = expanded.contains(node.id)
                Button {
                    if node.isFolder {
                        if open { expanded.remove(node.id) } else { expanded.insert(node.id) }
                    } else { model.openDocument(node.id) }
                } label: {
                    HStack(spacing: 6) {
                        if node.isFolder {
                            Image(systemName: open ? "chevron.down" : "chevron.right")
                                .font(.system(size: 8, weight: .semibold)).foregroundStyle(PiperTheme.secondary).frame(width: 10)
                        }
                        Text(node.title).font(PiperTheme.ui(12, weight: node.isFolder ? .medium : .regular)).lineLimit(1)
                            .foregroundStyle(node.isFolder || selected ? PiperTheme.ink : PiperTheme.secondary)
                        Spacer(minLength: 0)
                        if node.isFolder { Text("\(node.count)").font(PiperTheme.ui(10.5)).foregroundStyle(PiperTheme.faint) }
                    }
                    .padding(.leading, CGFloat(depth) * 14 + (node.isFolder ? 8 : 24)).padding(.trailing, 8).frame(height: 26)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .background(selected ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                    .overlay(alignment: .leading) { if selected && PiperTheme.isPage { Rectangle().fill(PiperTheme.accent).frame(width: 2) } }
                }.buttonStyle(.plain).help(node.id).accessibilityLabel(node.isFolder ? "\(node.title) folder" : node.title)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            if let url = try? model.repository.containedURL(node.id) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                    }
                if let children = node.children, open {
                    WikiTreeRows(nodes: children, expanded: $expanded, model: model, depth: depth + 1)
                }
            }
        }
    }
}

private struct WindowReference: NSViewRepresentable {
    var resolve: (NSWindow?) -> Void
    func makeNSView(context: Context) -> NSView { let view = NSView(); DispatchQueue.main.async { resolve(view.window) }; return view }
    func updateNSView(_ view: NSView, context: Context) { DispatchQueue.main.async { resolve(view.window) } }
}
