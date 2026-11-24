import Agents
import Captures
import AppKit
import SwiftUI

/// What the reader paper with the focus shows: a file, a note, or nothing.
/// The session card takes a file as context, and shows the sessions of a note.
enum SkillTarget: Equatable {
    /// A file in the folder. The argument is its path.
    case page(String)
    case note(UUID)
    case folder
}

/// Where the session shows: a pill in the corner of the focused reader
/// paper, a card over the corner, or a panel of its own over every app.
enum SessionPresentation: String {
    case pill
    case card
    case detached
}

/// The session that the card shows, and the folder and the page it works with.
///
/// While a note is open, the card shows the sessions of that note: the one
/// the reader picked, or else the newest. A new session belongs to the note.
/// While a file is open, the card works in the folder of the file. The open
/// file, or the link or the text of the open note, is the item on the screen.
@MainActor
struct SessionTarget {
    let model: AppModel

    private var runner: SessionRunner { model.agents.runner }

    var page: String? {
        if case .page(let path) = model.actionTarget { return path }
        return nil
    }

    /// The note on the screen, if any.
    var noteID: UUID? {
        if case .note(let id) = model.actionTarget { return id }
        return nil
    }

    /// The sessions of the open note, the newest change first. The hidden
    /// sessions of the Reader margin are not here.
    var noteSessions: [AgentSession] {
        guard let noteID else { return [] }
        return runner.sessions.filter { $0.noteID == noteID && $0.purpose == .session }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The folder of the session, the page, or the default folder.
    var folder: String {
        if noteID != nil, let session { return session.folder }
        if let id = model.selectedSession, let session = runner.session(id), session.noteID != nil { return session.folder }
        return page == nil ? model.library.agentFolder : model.library.vault.root.path
    }

    var session: AgentSession? {
        if let noteID {
            if let id = model.selectedSession, let session = runner.session(id), session.noteID == noteID { return session }
            if model.newSessionNote == noteID { return nil }
            return noteSessions.first
        }
        guard let id = model.selectedSession, let session = runner.session(id), session.folder == folder else { return nil }
        return session
    }

    /// The open file, or the link or the text of the open note.
    var screenItem: ScreenItem? {
        if let page { return ScreenItem(item: .file(page), title: URL(fileURLWithPath: page).lastPathComponent) }
        guard let noteID, let note = model.store.notes.first(where: { $0.id == noteID }) else { return nil }
        if note.isArticle, let url = note.articleURL {
            let item = ContextItem.link(url)
            return ScreenItem(item: item, title: note.reading?.title.map(CaptureText.firstLine) ?? item.label)
        }
        return ScreenItem(item: .note(note.text), title: CaptureText.firstLine(note.text))
    }
}

/// The pill or the card in the bottom right corner of a reader paper.
struct SessionOverlay: View {
    @Bindable var model: AppModel

    var body: some View {
        switch model.sessionPresentation {
        case .pill: SessionPill(model: model)
        case .card: SessionCard(model: model, detached: false)
        case .detached: EmptyView()
        }
    }
}

/// The conversation with an agent: a header, the transcript, and the composer.
///
/// The same view is the card in a reader paper and the content of the
/// detached panel.
struct SessionCard: View {

    // MARK: - Properties

    @Bindable var model: AppModel
    let detached: Bool
    @AppStorage(AppDefaults.Key.sessionCardHeight) private var height = Double(Metrics.height)
    @State private var dragStart: Double?
    /// True while the resize cursor is on the cursor stack.
    @State private var showsResizeCursor = false

    private var target: SessionTarget { SessionTarget(model: model) }
    private var runner: SessionRunner { model.agents.runner }

    var body: some View {
        let target = target
        let session = target.session
        VStack(spacing: 0) {
            header(session, folder: target.folder)
            Rule()
            SessionPane(model: model, session: session, folder: target.folder, noteID: target.noteID,
                        screenItem: target.screenItem,
                        started: { session in
                            model.selectedSession = session.id
                            model.newSessionNote = nil
                        })
        }
        .background(detached ? AnyShapeStyle(PiperTheme.paper) : AnyShapeStyle(.regularMaterial))
        .modifier(CardShape(detached: detached, height: height))
        .overlay(alignment: .top) { if !detached { resizeHandle } }
        .onExitCommand { if !detached { model.sessionPresentation = .pill } }
    }

    // MARK: - Parts

    private func header(_ session: AgentSession?, folder: String) -> some View {
        HStack(spacing: Metrics.headerSpacing) {
            AgentMark(kind: model.agents.kind(of: session?.agentID ?? model.agents.sessionAgentID))
                .font(.system(size: Metrics.agentMarkSize, weight: .semibold))
                .accessibilityHidden(true)
            sessionMenu(session, folder: folder)
            Spacer(minLength: Metrics.headerTitleGap)
            if let session { SessionStateChip(session: session) }
            IconButton(title: "New Session", icon: "square.and.pencil") { newSession() }
            if detached {
                IconButton(title: "Dock in the Paper", icon: "arrow.down.left.square") { model.sessionPresentation = .card }
            } else {
                IconButton(title: "Pop Out", icon: "arrow.up.right.square") { model.sessionPresentation = .detached }
                IconButton(title: "Collapse · Escape", icon: "chevron.down") { model.sessionPresentation = .pill }
            }
        }
        .padding(Metrics.headerPadding)
        .frame(height: Metrics.headerHeight)
    }

    private func sessionMenu(_ session: AgentSession?, folder: String) -> some View {
        Menu {
            Button("New Session") { newSession() }
            let sessions = target.noteID == nil ? runner.sessions(in: folder) : target.noteSessions
            if !sessions.isEmpty { Divider() }
            ForEach(sessions.prefix(Metrics.menuSessionLimit)) { item in
                Button {
                    model.selectedSession = item.id
                } label: {
                    Text(item.title)
                    Text(item.state.label + " · " + RowTime.text(item.updatedAt))
                }
            }
        } label: {
            Text(session?.title ?? "New Session in \(URL(fileURLWithPath: folder).lastPathComponent)")
                .font(PiperTheme.paperUI(.body, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: false, vertical: true)
        .help("Choose a session of this folder")
    }

    private func newSession() {
        model.selectedSession = nil
        model.newSessionNote = target.noteID
    }

    /// The top edge of the card. Drag it to change the height.
    private var resizeHandle: some View {
        Color.clear
            .frame(height: Metrics.resizeHandleHeight)
            .contentShape(Rectangle())
            .onHover { setResizeCursor($0) }
            .onDisappear { setResizeCursor(false) }
            .gesture(DragGesture(minimumDistance: Metrics.resizeDragDistance, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStart ?? height
                    dragStart = start
                    height = min(max(start - value.translation.height, Metrics.minimumHeight), Metrics.maximumHeight)
                }
                .onEnded { _ in dragStart = nil })
            .accessibilityHidden(true)
    }

    /// Pushes the resize cursor once, and pops only a cursor that it pushed.
    /// The card can go away under the pointer, so its disappearance pops too.
    private func setResizeCursor(_ shown: Bool) {
        guard shown != showsResizeCursor else { return }
        showsResizeCursor = shown
        if shown { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
    }
}

/// The session card in the corner of a reader paper, and its detached panel.
extension SessionCard {
    enum Metrics {
        static let width: CGFloat = 400
        static let height: CGFloat = 560
        static let minimumHeight: Double = 260
        static let maximumHeight: Double = 900
        static let cornerRadius: CGFloat = 16
        static let margin: CGFloat = 16
        static let headerHeight: CGFloat = 44
        static let pillHeight: CGFloat = 34
        static let pillMaximumWidth: CGFloat = 340
        /// The part of the reader paper that the card can cover at most.
        static let paneFraction: CGFloat = 0.85
        static let panelSize = NSSize(width: 420, height: 640)
        static let panelMinimumSize = NSSize(width: 340, height: 360)
        static let tabsMinimumWidth: CGFloat = 220
        static let headerSpacing: CGFloat = 6
        /// The least space after the session menu of the header.
        static let headerTitleGap: CGFloat = 4
        static let agentMarkSize: CGFloat = 14
        /// The line around the card and around the pill.
        static let edgeWidth: CGFloat = 0.5
        static let pillSpacing: CGFloat = 7
        /// The dot of a finished or failed session in the pill.
        static let pillDot: CGFloat = 7
        static let pillGlyph: CGFloat = 12
        /// The distance that the pointer moves before the top edge resizes the card.
        static let resizeDragDistance: CGFloat = 1
        static let headerPadding = EdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 8)
        static let pillPadding = EdgeInsets(top: 0, leading: 11, bottom: 0, trailing: 14)
        /// The number of sessions that the session menu of the header shows.
        static let menuSessionLimit = 20
        /// The height of the strip at the top edge that changes the height of the card.
        static let resizeHandleHeight: CGFloat = 6
        static let cardShadowRadius: CGFloat = 22
        static let cardShadowOffset: CGFloat = 10
        static let pillShadowRadius: CGFloat = 12
        static let pillShadowOffset: CGFloat = 4
        /// The distance of a new detached panel from the top and the right of the screen.
        static let panelScreenInset: CGFloat = 30
        /// The shadows of the card and of its pill.
        static let cardShadow = Color.black.opacity(0.2)
        static let pillShadow = Color.black.opacity(0.16)
    }
}

/// The card floats with a shadow and round corners. The detached panel has
/// its own window chrome.
private struct CardShape: ViewModifier {
    let detached: Bool
    let height: Double
    @Environment(PaperLayout.self) private var layout

    func body(content: Content) -> some View {
        if detached {
            content
        } else {
            content
                .frame(width: layout.cardWidth)
                .frame(minHeight: SessionCard.Metrics.minimumHeight, idealHeight: height, maxHeight: height)
                .clipShape(RoundedRectangle(cornerRadius: SessionCard.Metrics.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: SessionCard.Metrics.cornerRadius).strokeBorder(PiperTheme.paperRule, lineWidth: SessionCard.Metrics.edgeWidth))
                .shadow(color: SessionCard.Metrics.cardShadow, radius: SessionCard.Metrics.cardShadowRadius,
                        y: SessionCard.Metrics.cardShadowOffset)
                .padding(SessionCard.Metrics.margin)
                .padding(.bottom, layout.cardBottomInset)
        }
    }
}

/// The collapsed card: one line with the state of the session. Needs You
/// fills the pill with orange. A click opens the card.
struct SessionPill: View {
    @Bindable var model: AppModel

    var body: some View {
        let session = SessionTarget(model: model).session
        let needsYou = session?.state == .needsYou
        Button { model.sessionPresentation = .card } label: {
            HStack(spacing: SessionCard.Metrics.pillSpacing) {
                icon(session)
                Text(text(session)).lineLimit(1)
                if session?.isActive != true {
                    Text(Command.sessionCard.key?.glyph ?? "").font(PiperTheme.paperUI(.body)).foregroundStyle(needsYou ? PiperTheme.onAccentSecondary : PiperTheme.paperFaint)
                }
            }
            .font(PiperTheme.paperUI(.body))
            .foregroundStyle(needsYou ? PiperTheme.onAccent : PiperTheme.paperInk)
            .padding(SessionCard.Metrics.pillPadding)
            .frame(height: SessionCard.Metrics.pillHeight)
            .frame(maxWidth: SessionCard.Metrics.pillMaximumWidth)
            .background {
                if needsYou { Capsule().fill(PiperTheme.warning) } else { Capsule().fill(.regularMaterial) }
            }
            .overlay(Capsule().strokeBorder(PiperTheme.paperRule, lineWidth: SessionCard.Metrics.edgeWidth))
            .shadow(color: SessionCard.Metrics.pillShadow, radius: SessionCard.Metrics.pillShadowRadius,
                    y: SessionCard.Metrics.pillShadowOffset)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .padding(SessionCard.Metrics.margin)
        .help("Open the Session Card · " + (Command.sessionCard.key?.name ?? ""))
        .accessibilityLabel("Session: " + text(session))
    }

    @ViewBuilder private func icon(_ session: AgentSession?) -> some View {
        switch session?.state {
        case .running?, .waiting?:
            ProgressView().controlSize(.mini)
        case .idle? where session?.primaryFile != nil, .failed?:
            Circle().fill(session?.state.color ?? PiperTheme.paperMuted).frame(width: SessionCard.Metrics.pillDot, height: SessionCard.Metrics.pillDot)
        case .needsYou?:
            Image(systemName: AgentSession.State.needsYou.symbol ?? "").font(.system(size: SessionCard.Metrics.pillGlyph)).foregroundStyle(PiperTheme.onAccent)
        default:
            AgentMark(kind: model.agents.kind(of: session?.agentID ?? model.agents.sessionAgentID)).font(.system(size: SessionCard.Metrics.agentMarkSize, weight: .semibold))
        }
    }

    private func text(_ session: AgentSession?) -> String {
        guard let session, !session.blocks.isEmpty else { return "Ask about this page" }
        let label = session.state.label
        switch session.state {
        case .waiting: return session.title + " · " + label
        case .running: return session.lastStep ?? session.title
        case .needsYou: return label + " · " + session.title
        case .idle: return session.primaryFile.map { label + " · " + $0 } ?? session.title
        case .failed: return label + " · " + (session.failure?.components(separatedBy: .newlines).first ?? session.title)
        }
    }
}
