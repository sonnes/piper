import AppKit
import Captures
import Feeds
import SwiftUI

/// The feed paper: the column of tabs on its left edge, and the sheet with
/// the scoped list or the index of the active tab.
struct FeedPaperView: View {
    @Bindable var paper: FeedPaperModel
    @Bindable var model: AppModel
    /// The window of the paper, for the keyboard focus of the list.
    let window: () -> NSWindow?

    @State private var namingSection = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private typealias Metrics = AppDefaults.Papers

    var body: some View {
        // The active tab lies over the paper. The other tabs lie under it.
        ZStack(alignment: .topLeading) {
            tabs(.under)
            sheet
                .padding(.leading, Metrics.tabVisible)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { paper.paperHeight = $0 }
            tabs(.over)
        }
        .padding(Metrics.shadowInsets)
        // The title bar is hidden, so the paper starts at the top margin of the window.
        .ignoresSafeArea(.container, edges: .top)
        .environment(paper.marks)
        .sheet(isPresented: $namingSection) {
            NewSectionSheet(sections: model.store.sections) { name in
                guard model.store.chooseSection(name) else { return }
                namingSection = false
                paper.pick(.today(section: model.store.activeSection))
            }
        }
        .onChange(of: model.wikiPaths, initial: true) { paper.syncFolders() }
        .onChange(of: model.loading) { paper.recordFileCount() }
        .onChange(of: model.files.count) { paper.recordFileCount() }
        .onChange(of: model.store.sections) { _, sections in
            if case .today(let section?) = paper.state.scope, !sections.contains(section) { paper.pick(.today(section: nil)) }
        }
        // The alert goes on the feed paper only, so it cannot open twice.
        .alert("Piper", isPresented: Binding(
            get: { model.store.errorMessage != nil },
            set: { if !$0 { model.store.errorMessage = nil } }
        )) {
            Button("OK") { model.store.errorMessage = nil }
        } message: {
            Text(model.store.errorMessage ?? "")
        }
    }

    // MARK: - Parts

    private func tabs(_ layer: PaperTabs.Layer) -> some View {
        let tabs = paper.tabs
        let lengths = tabs.map { TabColumn.labelLength(title: $0.title, count: count($0)) }
        let addLength = TabColumn.labelLength(title: TabColumn.addLabel, count: 0)
        let removeFolder: ((String) -> Void)? = model.wikiPaths.count > 1 ? { model.removeWikiFolder($0) } : nil
        return PaperTabs(layer: layer, tabs: tabs, active: paper.state.tab, color: paper.color(of:), count: count,
                         stubs: TabColumn.usesStubs(lengths: lengths, addLength: addLength, paperHeight: paper.paperHeight),
                         choose: paper.choose, addFolder: paper.addFolder,
                         removeFolder: removeFolder)
            .padding(.top, Metrics.tabsTop)
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                if paper.showsIndex {
                    FeedPaperIndex(paper: paper, model: model).transition(.opacity)
                } else {
                    list.transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : .easeInOut(duration: Metrics.fade), value: paper.showsIndex)
        }
        .background(PiperTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .paperShadow(focused: paper.marks.feedFocused)
        .foregroundStyle(PiperTheme.paperInk)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            // The title takes the room first. It shrinks before it truncates.
            Text(paper.showsIndex ? paper.state.tab.title : title)
                .font(PiperTheme.paperTitle(.title))
                .lineLimit(1).minimumScaleFactor(Metrics.titleMinimumScale).truncationMode(.tail)
                .layoutPriority(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if paper.showsIndex {
                Button(action: paper.showList) {
                    HStack(spacing: 8) {
                        Text("Back to the list")
                        KeyCap(text: "esc")
                    }
                    .font(PiperTheme.paperUI(.body, weight: .medium))
                    .foregroundStyle(PiperTheme.paperMuted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show the list · Escape")
            } else {
                // The date leaves the header when the title needs its room.
                ViewThatFits {
                    Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                        .fixedSize()
                    Color.clear.frame(width: 0, height: 0)
                }
                moreMenu
            }
        }
        .padding(Metrics.headerPadding)
        .background(WindowDragArea())
    }

    private var moreMenu: some View {
        Menu {
            Button("New Capture") { paper.newCapture() }
            Button("New Section…") { namingSection = true }
            Button("Add Folder…") { paper.addFolder() }
            Button("Sources…") { paper.showSources() }
            Divider()
            Button("Show in Finder") { NSWorkspace.shared.open(model.vault.root) }
            if case .folder(let path) = paper.state.tab, model.wikiPaths.count > 1 {
                Button("Remove Folder") { model.removeWikiFolder(path) }
            }
            Button("Refresh") { model.reload() }
            Button("Settings…") { model.openSettings?() }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 16)).foregroundStyle(PiperTheme.paperMuted)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("More").accessibilityLabel("More")
    }

    @ViewBuilder private var list: some View {
        switch paper.state.scope {
        case .today, .done:
            TodayView(today: paper.today, paper: paper, model: model, window: window)
        case .feed(let feed):
            FeedArticleList(model: model, feedID: feed, selectedID: paper.selectedArticle,
                            select: { paper.selectedArticle = $0?.id },
                            openPaper: { paper.open(.article($0.id)) },
                            setKeys: { paper.listKeys = $0 })
        case .sources:
            SourcesView(paper: paper, model: model)
        case .folder:
            FolderTreeView(paper: paper, model: model)
        case .sessions(let folder):
            SessionList(model: model, folder: folder, open: paper.open, setKeys: { paper.listKeys = $0 })
        }
    }

    // MARK: - Text

    /// The tab and the scope, for example "Today › Harbor".
    private var title: String {
        let tab = paper.state.tab
        switch paper.state.scope {
        case .today(nil): return "Today"
        case .today(let section?): return "Today › " + section
        case .done: return "Today › Done"
        case .feed(let id): return "Today › " + (model.feeds.feed(id)?.title ?? "Feed")
        case .sources: return "Today › Sources"
        case .folder:
            return tab.title
        case .sessions(let folder): return "Agents › " + URL(fileURLWithPath: folder).lastPathComponent
        }
    }

    /// The count on a tab.
    private func count(_ tab: PaperTab) -> Int {
        switch tab {
        case .today: return model.store.notes.filter { $0.parent == nil && !$0.isDone }.count
        case .agents:
            let runner = model.agents.runner
            return runner.folders().reduce(0) { total, folder in
                total + runner.sessions(in: folder).filter { $0.state == .needsYou }.count
            }
        case .folder(let path): return paper.fileCount(of: path)
        }
    }
}

/// A key on the keyboard, such as esc.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(PiperTheme.paperUI(.body, weight: .medium))
            .foregroundStyle(PiperTheme.paperMuted)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(PiperTheme.paper, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(PiperTheme.paperRule, lineWidth: 1))
    }
}
