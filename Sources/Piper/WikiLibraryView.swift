import AppKit
import SwiftUI

enum WikiStyle {
    static let paper = PiperTheme.page
    static let sidebar = PiperTheme.surface
    static let hairline = PiperTheme.rule
}

struct LibraryView: View {
    @Bindable var model: AppModel
    @State private var showSidebar = true
    @AppStorage("wikiInspectorVisible") private var showInspector = true
    @State private var focused = false
    @State private var expanded: Set<String> = []
    @State private var initializedTree = false
    @State private var monitor: Any?
    @State private var window: NSWindow?
    @AppStorage("wikiReaderSize") private var readerSize = 18.0
    @AppStorage("wikiReaderTheme") private var readerTheme = WikiReadingTheme.paper
    @AppStorage("wikiReaderFont") private var readerFont = WikiReadingFont.mono
    @AppStorage("wikiReaderAppearance") private var readerAppearance = WikiReadingAppearance.system
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if showSidebar && !focused { sidebar.frame(width: 234); Divider() }
                VStack(spacing: 0) {
                    toolbar
                    Divider()
                    if model.route == "settings" { SettingsView(model: model).frame(maxWidth: .infinity, maxHeight: .infinity) }
                    else { workspace }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if showInspector && !focused && model.route == "wiki", let document = model.currentDocument {
                    Divider()
                    WikiInspector(model: model, document: document, theme: $readerTheme, font: $readerFont,
                                  fontSize: $readerSize, appearance: $readerAppearance,
                                  focus: { focused = true }, close: { showInspector = false })
                        .frame(width: 274)
                }
            }
            Divider()
            statusBar
        }
        .background(WikiStyle.paper)
        .foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.accent)
        .accentColor(PiperTheme.accent)
        .preferredColorScheme(readerAppearance.colorScheme)
        .frame(minWidth: 850, minHeight: 600)
        .background(WindowReference { window = $0; $0?.isDocumentEdited = model.wikiEdit?.hasChanges == true })
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                if let mark = PiperTheme.mark {
                    Image(nsImage: mark).renderingMode(.template).resizable().scaledToFit()
                        .foregroundStyle(PiperTheme.accent).frame(width: 28, height: 25).accessibilityHidden(true)
                }
                Text("Wiki").font(.system(size: 18, weight: .medium))
                Spacer()
                Button { model.openPanel?() } label: { Image(systemName: "square.and.pencil") }
                    .buttonStyle(.plain).help("Open Capture Panel · ⌘1").accessibilityLabel("Open Capture Panel")
            }.padding(.horizontal, 20).frame(height: 58)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(PiperTheme.secondary)
                TextField("Search Wiki", text: $model.wikiQuery).textFieldStyle(.plain).font(.system(size: 12))
                    .focused($searching).accessibilityLabel("Search Wiki")
                    .onSubmit { if let first = model.filteredDocuments.first { model.openDocument(first.id) } }
                if !model.wikiQuery.isEmpty {
                    Button { model.wikiQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(PiperTheme.secondary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear Wiki Search")
                } else { Text("⌘O").font(.system(size: 10)).foregroundStyle(PiperTheme.secondary) }
            }.padding(.horizontal, 10).frame(height: 32)
                .overlay(alignment: .bottom) { Rectangle().fill(PiperTheme.control).frame(height: 1) }
                .padding(.horizontal, 14).padding(.bottom, 19)
            HStack {
                Text(model.wikiQuery.isEmpty ? "FILES" : "\(model.filteredDocuments.count) RESULTS")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(PiperTheme.secondary)
                Spacer()
                if model.wikiQuery.isEmpty {
                    Button { expanded = expanded.isEmpty ? allFolders : [] } label: { Image(systemName: "arrow.up.and.down.text.horizontal") }
                        .help(expanded.isEmpty ? "Expand Folders" : "Collapse Folders").accessibilityLabel("Toggle Folders")
                }
                Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(model.loading).help("Refresh Wiki · ⌘R").accessibilityLabel("Refresh Wiki")
            }.buttonStyle(.plain).font(.system(size: 11)).padding(.horizontal, 20).padding(.bottom, 9)
            ScrollView {
                if model.wikiQuery.isEmpty {
                    WikiTreeRows(nodes: WikiTreeNode.build(model.documents), expanded: $expanded, model: model)
                        .padding(.horizontal, 9)
                } else if model.filteredDocuments.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("No matching notes").font(.system(size: 13, weight: .medium))
                        Text("Try a title, phrase, or folder name.").font(.system(size: 12)).foregroundStyle(PiperTheme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
                } else {
                    LazyVStack(spacing: 4) {
                        ForEach(model.filteredDocuments) { document in
                            Button { openFromExplorer(document.id) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(document.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                                    Text(searchExcerpt(document)).font(.system(size: 11)).foregroundStyle(PiperTheme.secondary).lineLimit(3)
                                    Text(document.folder.isEmpty ? "Wiki" : document.folder).font(.system(size: 10)).foregroundStyle(PiperTheme.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                    .background(model.selectedDocument == document.id ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 3))
                                    .overlay(alignment: .leading) { if model.selectedDocument == document.id { Rectangle().fill(PiperTheme.accent).frame(width: 2) } }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 9)
                }
            }.scrollIndicators(.automatic)
            if !model.wikiProblems.isEmpty {
                DisclosureGroup("\(model.wikiProblems.count) file warnings") {
                    Text(model.wikiProblems.joined(separator: "\n")).textSelection(.enabled).font(.system(size: 10)).padding(.top, 5)
                }.font(.system(size: 11)).foregroundStyle(.orange).padding(14)
            }
            Divider().padding(.horizontal, 14)
            HStack(spacing: 9) {
                Image(systemName: "externaldrive").font(.system(size: 16)).foregroundStyle(PiperTheme.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.repository.root.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text("Local Wiki").font(.system(size: 10)).foregroundStyle(PiperTheme.secondary)
                }
                Spacer()
                Menu {
                    Button("Choose Wiki Folder…") { model.chooseWiki() }
                    Button("Reveal Wiki in Finder") { NSWorkspace.shared.open(model.repository.root) }
                    Divider()
                    Button("Settings…") { model.route = "settings" }
                } label: { Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Wiki Folder Options")
            }.padding(.horizontal, 19).frame(height: 64)
        }.background(WikiStyle.sidebar)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                iconButton("Toggle File Sidebar", icon: "sidebar.left", active: showSidebar && !focused) {
                    if focused { focused = false; showSidebar = true } else { showSidebar.toggle() }
                }
                iconButton("Back · ⌘[", icon: "chevron.left") { model.navigate(-1) }.disabled(!model.workspace.canGoBack)
                iconButton("Forward · ⌘]", icon: "chevron.right") { model.navigate(1) }.disabled(!model.workspace.canGoForward)
            }.frame(width: 120, alignment: .leading)
            Spacer(minLength: 0)
            Text(model.route == "settings" ? "Settings" : model.currentDocument?.title ?? "Wiki")
                .font(.system(size: 13, weight: .medium)).lineLimit(1)
                .help(model.currentDocument?.id ?? "Wiki")
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                if model.route == "settings" {
                    Button("Done") { model.route = "wiki" }.buttonStyle(.plain)
                } else if model.currentDocument != nil {
                    iconButton("Document Sidebar", icon: "sidebar.right", active: showInspector && !focused) {
                        if focused { focused = false; showInspector = true } else { showInspector.toggle() }
                    }
                }
            }.frame(width: 120, alignment: .trailing)
        }.padding(.horizontal, 18).frame(height: 48)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            if let error = model.wikiError {
                ContentUnavailableView {
                    Label("Wiki Unavailable", systemImage: "folder.badge.questionmark")
                } description: { Text(error) } actions: {
                    Button("Create Wiki Here") { model.createWiki() }
                    Button("Choose Wiki Folder") { model.chooseWiki() }
                    Button("Retry") { model.reload() }
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
                        Button("Create Wiki") { model.createWiki() }
                        Button("Open Capture Panel") { model.openPanel?() }
                    }
                    else { Button("Search Wiki") { focusSearch() } }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var readingPaper: Color { Color(nsColor: readerTheme.background(dark: (readerAppearance.colorScheme ?? colorScheme) == .dark)) }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: model.loading ? "arrow.triangle.2.circlepath" : "internaldrive").font(.system(size: 10))
            Text("Local Wiki")
            Text("·").foregroundStyle(PiperTheme.secondary)
            Text("\(model.documents.count) files")
            Spacer()
            if focused { Text("Focus"); Text("·").foregroundStyle(PiperTheme.secondary) }
            if let document = model.currentDocument {
                let words = (model.wikiEdit?.markdown ?? document.body).split { $0.isWhitespace || $0.isNewline }.count
                Text("\(words.formatted()) words")
                Text("·").foregroundStyle(PiperTheme.secondary)
                if let edit = model.wikiEdit { Text(edit.hasChanges ? "Unsaved changes" : "Saved") }
                else { Text("\(max(1, Int(ceil(Double(words) / 220)))) min read") }
            }
        }.font(.system(size: 10)).foregroundStyle(PiperTheme.secondary).padding(.horizontal, 17).frame(height: 27)
    }

    private func iconButton(_ title: String, icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 13)).frame(width: 26, height: 28).contentShape(Rectangle()) }
            .buttonStyle(.plain).foregroundStyle(active ? PiperTheme.ink : PiperTheme.secondary).help(title).accessibilityLabel(title)
    }

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

    private func openFromExplorer(_ path: String) {
        model.openDocument(path)
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
        VStack(spacing: 2) {
            ForEach(nodes) { node in
                Button {
                    if node.isFolder {
                        if expanded.contains(node.id) { expanded.remove(node.id) } else { expanded.insert(node.id) }
                    } else { model.openDocument(node.id) }
                } label: {
                    HStack(spacing: 7) {
                        if node.isFolder {
                            Image(systemName: expanded.contains(node.id) ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .semibold)).frame(width: 9)
                            Image(systemName: expanded.contains(node.id) ? "folder.fill" : "folder").font(.system(size: 12)).foregroundStyle(PiperTheme.secondary)
                        } else {
                            Image(systemName: "doc.text").font(.system(size: 11)).foregroundStyle(PiperTheme.secondary).frame(width: 13)
                        }
                        Text(node.title).font(.system(size: 12, weight: node.isFolder ? .medium : .regular)).lineLimit(1)
                        Spacer(minLength: 0)
                        if node.isFolder { Text("\(node.count)").font(.system(size: 10)).foregroundStyle(PiperTheme.secondary) }
                    }.padding(.leading, CGFloat(depth) * 13 + 10).padding(.trailing, 10).frame(height: 30)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        .background(!node.isFolder && model.selectedDocument == node.id ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 3))
                        .overlay(alignment: .leading) { if !node.isFolder && model.selectedDocument == node.id { Rectangle().fill(PiperTheme.accent).frame(width: 2) } }
                }.buttonStyle(.plain).help(node.id).accessibilityLabel(node.isFolder ? "\(node.title) folder" : node.title)
                    .contextMenu {
                        Button("Reveal in Finder") {
                            if let url = try? model.repository.containedURL(node.id) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                    }
                if let children = node.children, expanded.contains(node.id) {
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
