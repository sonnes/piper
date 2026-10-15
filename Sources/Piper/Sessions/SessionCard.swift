import Agents
import AppKit
import SwiftUI

/// Where the session shows in the main window: a pill in the corner of the detail
/// pane, a card over the corner, or a panel of its own over every app.
enum SessionPresentation: String {
    case pill
    case card
    case detached
}

/// The session that the card shows, and the folder and the page it works with.
///
/// While a note is open, the card shows the sessions of that note: the one
/// the reader picked, or else the newest. A new session belongs to the note.
/// While a file is open, the card works in the folder of the file, and the
/// file is the context of the next message until the reader removes it or
/// sends one.
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
        if case .text(_, let id) = model.actionTarget { return id }
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
        return page == nil ? model.agents.defaultFolder?.path ?? model.vault.root.path : model.vault.root.path
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
}

/// The pill or the card in the bottom right corner of the detail pane.
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
/// The same view is the card in the main window and the content of the
/// detached panel.
struct SessionCard: View {

    // MARK: - Properties

    @Bindable var model: AppModel
    let detached: Bool
    /// The page that the reader removed from the context, or that a message took.
    @State private var usedContext: String?
    @AppStorage(AppDefaults.Key.sessionCardHeight) private var height = Double(AppDefaults.SessionCard.height)
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
                        context: session?.noteID == nil ? target.page.map { $0 == usedContext ? [] : [$0] } ?? [] : [],
                        contextUsed: { usedContext = target.page },
                        started: { session in
                            model.selectedSession = session.id
                            model.newSessionNote = nil
                        })
        }
        .background(detached ? AnyShapeStyle(PiperTheme.page) : AnyShapeStyle(.regularMaterial))
        .modifier(CardShape(detached: detached, height: height))
        .overlay(alignment: .top) { if !detached { resizeHandle } }
        .onChange(of: target.page) { _, _ in usedContext = nil }
        .onExitCommand { if !detached { model.sessionPresentation = .pill } }
    }

    // MARK: - Parts

    private func header(_ session: AgentSession?, folder: String) -> some View {
        HStack(spacing: 6) {
            AgentMark(agentID: session?.agentID ?? model.agents.sessionAgentID)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            sessionMenu(session, folder: folder)
            Spacer(minLength: 4)
            if let session { SessionStateChip(session: session) }
            IconButton(title: "New Session", icon: "square.and.pencil") { newSession() }
            if detached {
                IconButton(title: "Dock in the Main Window", icon: "arrow.down.left.square") { model.sessionPresentation = .card }
            } else {
                IconButton(title: "Pop Out", icon: "arrow.up.right.square") { model.sessionPresentation = .detached }
                IconButton(title: "Collapse · Escape", icon: "chevron.down") { model.sessionPresentation = .pill }
            }
        }
        .padding(AppDefaults.SessionCard.headerPadding)
        .frame(height: AppDefaults.SessionCard.headerHeight)
    }

    private func sessionMenu(_ session: AgentSession?, folder: String) -> some View {
        Menu {
            Button("New Session") { newSession() }
            let sessions = target.noteID == nil ? runner.sessions(in: folder) : target.noteSessions
            if !sessions.isEmpty { Divider() }
            ForEach(sessions.prefix(AppDefaults.SessionCard.menuSessionLimit)) { item in
                Button {
                    model.selectedSession = item.id
                } label: {
                    Text(item.title)
                    Text(SessionStateChip.title(item.state) + " · " + RowTime.text(item.updatedAt))
                }
            }
        } label: {
            Text(session?.title ?? "New Session in \(URL(fileURLWithPath: folder).lastPathComponent)")
                .font(PiperTheme.ui(13, weight: .semibold))
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
            .frame(height: AppDefaults.SessionCard.resizeHandleHeight)
            .contentShape(Rectangle())
            .onHover { setResizeCursor($0) }
            .onDisappear { setResizeCursor(false) }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let start = dragStart ?? height
                    dragStart = start
                    height = min(max(start - value.translation.height, AppDefaults.SessionCard.minimumHeight), AppDefaults.SessionCard.maximumHeight)
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

/// The card floats with a shadow and round corners. The detached panel has
/// its own window chrome.
private struct CardShape: ViewModifier {
    let detached: Bool
    let height: Double
    @Environment(DetailPaneLayout.self) private var layout

    func body(content: Content) -> some View {
        if detached {
            content
        } else {
            content
                .frame(width: layout.cardWidth)
                .frame(minHeight: AppDefaults.SessionCard.minimumHeight, idealHeight: height, maxHeight: height)
                .clipShape(RoundedRectangle(cornerRadius: AppDefaults.SessionCard.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: AppDefaults.SessionCard.cornerRadius).strokeBorder(PiperTheme.rule, lineWidth: 0.5))
                .shadow(color: PiperTheme.sessionCardShadow, radius: AppDefaults.SessionCard.cardShadowRadius,
                        y: AppDefaults.SessionCard.cardShadowOffset)
                .padding(AppDefaults.SessionCard.margin)
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
            HStack(spacing: 7) {
                icon(session)
                Text(text(session)).lineLimit(1)
                if session?.isActive != true {
                    Text("⌥⌘C").font(PiperTheme.ui(11)).foregroundStyle(needsYou ? PiperTheme.onAccentSecondary : PiperTheme.faint)
                }
            }
            .font(PiperTheme.ui(12.5))
            .foregroundStyle(needsYou ? PiperTheme.onAccent : PiperTheme.ink)
            .padding(AppDefaults.SessionCard.pillPadding)
            .frame(height: AppDefaults.SessionCard.pillHeight)
            .frame(maxWidth: AppDefaults.SessionCard.pillMaximumWidth)
            .background {
                if needsYou { Capsule().fill(PiperTheme.warning) } else { Capsule().fill(.regularMaterial) }
            }
            .overlay(Capsule().strokeBorder(PiperTheme.rule, lineWidth: 0.5))
            .shadow(color: PiperTheme.sessionPillShadow, radius: AppDefaults.SessionCard.pillShadowRadius,
                    y: AppDefaults.SessionCard.pillShadowOffset)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .padding(AppDefaults.SessionCard.margin)
        .help("Open the Session Card · Option-Command-C")
        .accessibilityLabel("Session: " + text(session))
    }

    @ViewBuilder private func icon(_ session: AgentSession?) -> some View {
        switch session?.state {
        case .running?, .waiting?:
            ProgressView().controlSize(.mini)
        case .idle? where session?.primaryFile != nil:
            Circle().fill(PiperTheme.success).frame(width: 7, height: 7)
        case .failed?:
            Circle().fill(PiperTheme.danger).frame(width: 7, height: 7)
        case .needsYou?:
            Image(systemName: "exclamationmark.bubble.fill").font(.system(size: 12)).foregroundStyle(PiperTheme.onAccent)
        default:
            AgentMark(agentID: session?.agentID ?? model.agents.sessionAgentID).font(.system(size: 13, weight: .semibold))
        }
    }

    private func text(_ session: AgentSession?) -> String {
        guard let session, !session.blocks.isEmpty else { return "Ask about this page" }
        switch session.state {
        case .waiting: return session.title + " · Waiting"
        case .running: return session.lastStep ?? session.title
        case .needsYou: return "Needs you · " + session.title
        case .idle: return session.primaryFile.map { "Done · " + $0 } ?? session.title
        case .failed: return "Failed · " + (session.failure?.components(separatedBy: .newlines).first ?? session.title)
        }
    }
}
