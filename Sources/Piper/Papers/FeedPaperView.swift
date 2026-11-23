import AppKit
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
        HStack(alignment: .top, spacing: -Metrics.tabOverlap) {
            PaperTabs(tabs: paper.column.tabs, active: paper.state.tab, count: count, choose: paper.choose)
                .padding(.top, Metrics.tabsTop)
            sheet.zIndex(1)
        }
        .sheet(isPresented: $model.addingFeed) {
            AddFeedSheet(feeds: model.feeds) { added in
                model.addingFeed = false
                guard let added else { return }
                paper.choose(.feeds)
                paper.pick(.feed(.feed(added)))
            }
        }
        .sheet(isPresented: $namingSection) {
            NewSectionSheet(sections: model.store.sections) { name in
                guard model.store.chooseSection(name) else { return }
                namingSection = false
                paper.choose(.inbox)
                paper.pick(.inbox(section: model.store.activeSection))
            }
        }
        .onChange(of: model.store.sections) { _, sections in
            if case .inbox(let section?) = paper.state.scope, !sections.contains(section) { paper.pick(.inbox(section: nil)) }
        }
        .routeSheets(model)
    }

    // MARK: - Parts

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
        .foregroundStyle(PiperTheme.paperInk)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(paper.showsIndex ? paper.state.tab.title : title)
                .font(PiperTheme.paperTitle(.title))
                .lineLimit(1).truncationMode(.middle)
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
                if case .folder(let path) = paper.state.scope {
                    let folder = path.isEmpty ? model.vault.root.path : model.vault.root.appendingPathComponent(path).path
                    let pinned = paper.state.pinnedFolders.contains(folder)
                    PaperButton(title: pinned ? "Unpin" : "Pin", symbol: pinned ? "pin.fill" : "pin", active: pinned,
                                help: pinned ? "Remove the tab of this folder" : "Add a tab for this folder") {
                        paper.togglePin(folder)
                    }
                    .font(PiperTheme.paperUI(.body, weight: .medium))
                }
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
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
            Button("Add Folder…") { model.chooseWiki() }
            Button("Add Feed…") { model.addingFeed = true }
            Divider()
            Button("Reveal in Finder") { NSWorkspace.shared.open(model.vault.root) }
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
        case .inbox(let section): captureView(.stream(section: section))
        case .done: captureView(.archived)
        case .clipboard: captureView(.clipboard)
        case .feed(.discover): DiscoverView(model: model)
        case .feed(let filter):
            FeedArticleList(model: model, filter: filter, selectedID: paper.selectedArticle,
                            select: { paper.selectedArticle = $0?.id },
                            openPaper: { paper.open(.article($0.id)) })
        case .folder(let path):
            FolderListView(model: model, folder: path) { file in
                model.openDocument(file)
                paper.open(.file)
            }
        case .sessions(let folder):
            SessionList(model: model, folder: folder, open: paper.open)
        }
    }

    private func captureView(_ content: CaptureListContent) -> CaptureView {
        CaptureView(
            model: model, embedded: true, content: content,
            composerRequest: paper.composerRequest,
            acceptsKeyboard: { [paper] window in
                window.windowController is FeedPaperController && !paper.showsIndex
            },
            focusNotes: { window()?.makeFirstResponder(nil) },
            openCapture: { paper.open(.note($0)) }
        )
    }

    // MARK: - Text

    /// The tab and the scope, for example "Feeds › Harbor Notes".
    private var title: String {
        let tab = paper.state.tab
        switch paper.state.scope {
        case .inbox(nil): return "Inbox"
        case .inbox(let section?): return "Inbox › " + section
        case .done: return "Inbox › Done"
        case .clipboard: return "Clipboard"
        case .feed(let filter):
            switch filter {
            case .discover: return "Feeds › Discover"
            case .allUnread: return "Feeds › All Unread"
            case .starred: return "Feeds › Starred"
            case .feed(let id): return "Feeds › " + (model.feeds.feed(id)?.title ?? "Feed")
            }
        case .folder(let path):
            let name = path.isEmpty ? model.vault.root.lastPathComponent : (path as NSString).lastPathComponent
            if case .pinned = tab { return name }
            return "Folders › " + name
        case .sessions(let folder): return "Agents › " + URL(fileURLWithPath: folder).lastPathComponent
        }
    }

    /// The count on a tab.
    private func count(_ tab: PaperTab) -> Int {
        switch tab {
        case .inbox: return model.store.notes.filter { $0.parent == nil && !$0.isDone }.count
        case .clipboard: return model.clipboard.entries.count
        case .feeds: return model.feeds.totalUnread
        case .folders: return model.files.count
        case .agents:
            let runner = model.agents.runner
            return runner.folders().reduce(0) { total, folder in
                total + runner.sessions(in: folder).filter { $0.state == .needsYou }.count
            }
        case .pinned(let path):
            guard let folder = PaperDeskState.relativePath(of: path, in: model.vault.root.path) else { return 0 }
            return FolderListView.groups(model.files, in: folder).reduce(0) { $0 + $1.files.count }
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
