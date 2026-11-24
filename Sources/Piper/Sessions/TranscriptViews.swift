import Agents
import AppKit
import SwiftUI
import Vault

/// One block of a transcript.
struct TranscriptBlockView: View {
    let files: FileEditor
    let session: AgentSession
    let block: TranscriptBlock

    var body: some View {
        switch block {
        case .user(_, let text, let context):
            UserTurnView(text: text, context: context)
        case .assistant(_, let text):
            AssistantTextView(text: text)
        case .toolCall(let call):
            ToolCallRow(call: call, isLive: session.isActive) { path in
                files.openRunFile(path, in: session.folder)
            }
        case .permission(let request, let decision):
            PermissionCard(request: request, decision: decision, folderName: session.folderName)
        case .question(let request, let answers):
            if let answers {
                QuestionCard(request: request, answers: answers) { _ in }
            } else {
                WaitingLine(text: "A question waits for your answer below the transcript")
            }
        case .result(_, let result):
            ResultRow(result: result)
        }
    }
}

extension TranscriptBlockView {
    /// The blocks of a session transcript.
    enum Metrics {
        /// The space between blocks of a transcript, and the inset of the transcript.
        static let blockSpacing: CGFloat = 10
        static let transcriptInset = EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        /// A message of the reader is a bubble. Its corner at the bottom right is small, like a tail.
        static let bubbleRadius: CGFloat = 14
        static let bubbleTailRadius: CGFloat = 4
        static let bubblePadding = EdgeInsets(top: 7, leading: 11, bottom: 7, trailing: 11)
        /// The bubble leaves at least this much of the transcript width empty on its left.
        static let bubbleLeadingSpace: CGFloat = 64
        /// A tool row, a diff, and the fold.
        static let chipRadius: CGFloat = 8
        static let chipPadding = EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
        /// The number of diff lines that an Edit row shows.
        static let diffLineLimit = 12
        /// The lines that an edit adds and removes.
        static let diffAdded = Color(nsColor: PiperTheme.hex(0x22C55E)).opacity(0.14)
        static let diffRemoved = Color(nsColor: PiperTheme.hex(0xEF4444)).opacity(0.12)
        /// The mark of a finished tool call. Green 600.
        static let toolDone = Color(nsColor: PiperTheme.color(light: 0x16A34A, dark: 0x4ADE80))
        /// The space between a bubble and the context items under it.
        static let contextSpacing: CGFloat = 4
        static let bubbleLineSpacing: CGFloat = 3
        static let assistantLineSpacing: CGFloat = 3.5
        /// The space between a tool row and the start of its result.
        static let toolSpacing: CGFloat = 4
        /// The space between the icon and the text of a tool row and of the fold.
        static let chipSpacing: CGFloat = 7
        /// The width of the icon of a tool row and of the fold.
        static let chipIconWidth: CGFloat = 12
        static let toolLineFontSize: CGFloat = 12
        static let toolPreviewFontSize: CGFloat = 11
        static let toolStatusGlyph: CGFloat = 10
        /// The least space before the Open button of a tool row.
        static let toolOpenGap: CGFloat = 4
        /// The line around a tool result and a diff.
        static let edgeWidth: CGFloat = 1
        static let diffFontSize: CGFloat = 11.5
        static let diffLineInset: CGFloat = 9
        static let diffLineVerticalPadding: CGFloat = 1
        static let diffMoreVerticalPadding: CGFloat = 3
        /// The space between the icon and the text of a one-line block, such as a permission.
        static let lineIconSpacing: CGFloat = 6
        /// The open fold: the space between its tool calls, their indent, and the rule beside them.
        static let foldSpacing: CGFloat = 6
        static let foldIndent: CGFloat = 12
        static let foldRuleWidth: CGFloat = 1
        static let foldRuleInset: CGFloat = 6
        static let foldChevronGlyph: CGFloat = 9
        /// The turn of the chevron of an open fold, in degrees.
        static let foldOpenRotation: Double = 90
        /// The height of the empty view at the end of a transcript, which the transcript scrolls to.
        static let endMarkerHeight: CGFloat = 1
    }
}

/// A message from the reader, as a bubble on the right, with the items it
/// named as context under it.
struct UserTurnView: View {
    let text: String
    let context: [ContextItem]

    private typealias Metrics = TranscriptBlockView.Metrics

    var body: some View {
        VStack(alignment: .trailing, spacing: Metrics.contextSpacing) {
            Text(text)
                .font(PiperTheme.paperUI(.row))
                .lineSpacing(Metrics.bubbleLineSpacing)
                .foregroundStyle(PiperTheme.onAccent)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Metrics.bubblePadding)
                .background(PiperTheme.brand, in: UnevenRoundedRectangle(
                    topLeadingRadius: Metrics.bubbleRadius, bottomLeadingRadius: Metrics.bubbleRadius,
                    bottomTrailingRadius: Metrics.bubbleTailRadius, topTrailingRadius: Metrics.bubbleRadius))
            ForEach(context, id: \.self) { item in
                Label(item.label, systemImage: item.icon)
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                    .lineLimit(1)
                    .help(item.argument)
            }
        }
        .padding(.leading, Metrics.bubbleLeadingSpace)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// A message from the agent, as plain text. Inline Markdown shows as formatted text.
struct AssistantTextView: View {
    let text: String

    private var formatted: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    var body: some View {
        Text(formatted)
            .font(PiperTheme.paperUI(.row))
            .lineSpacing(TranscriptBlockView.Metrics.assistantLineSpacing)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One tool call, as a small gray chip in a monospaced font. A call with an
/// edit shows its lines in a diff card. A click shows the start of the result.
struct ToolCallRow: View {
    let call: ToolCall
    /// True while the session can still finish the call.
    let isLive: Bool
    let open: (String) -> Void
    @State private var expanded = false

    private typealias Metrics = TranscriptBlockView.Metrics

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.toolSpacing) {
            if let diff = call.diff {
                DiffView(diff: diff) { header }
            } else {
                header
                    .padding(Metrics.chipPadding)
                    .background(PiperTheme.rowHover, in: RoundedRectangle(cornerRadius: Metrics.chipRadius))
            }
            if expanded, let preview = call.resultPreview {
                Text(preview)
                    .font(Font(PiperTheme.manuscript(size: Metrics.toolPreviewFontSize)))
                    .foregroundStyle(call.isError ? PiperTheme.danger : PiperTheme.paperMuted)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metrics.chipPadding)
                    .overlay(RoundedRectangle(cornerRadius: Metrics.chipRadius).strokeBorder(PiperTheme.paperRule, lineWidth: Metrics.edgeWidth))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(call.line)
    }

    private var header: some View {
        HStack(spacing: Metrics.chipSpacing) {
            status.frame(width: Metrics.chipIconWidth)
            Text(call.line)
                .font(Font(PiperTheme.manuscript(size: Metrics.toolLineFontSize)))
                .foregroundStyle(PiperTheme.paperMuted)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: Metrics.toolOpenGap)
            if let path = call.path, VaultFile.isMarkdown(path), !call.isError {
                Button("Open") { open(path) }.buttonStyle(.link).font(PiperTheme.paperUI(.body))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if call.resultPreview != nil { expanded.toggle() } }
    }

    @ViewBuilder private var status: some View {
        if call.isError {
            Image(systemName: "xmark").font(.system(size: Metrics.toolStatusGlyph, weight: .bold)).foregroundStyle(PiperTheme.danger)
        } else if call.isFinished {
            Image(systemName: "checkmark").font(.system(size: Metrics.toolStatusGlyph, weight: .bold)).foregroundStyle(Metrics.toolDone)
        } else if isLive {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(PiperTheme.paperFaint)
        }
    }
}

/// The lines that an edit removes and adds, in a card with a header row.
struct DiffView<Header: View>: View {
    let diff: ToolCall.Diff
    @ViewBuilder let header: Header

    private typealias Metrics = TranscriptBlockView.Metrics
    private var lines: [DiffText.Line] { DiffText.lines(old: diff.old, new: diff.new) }

    var body: some View {
        let shown = Array(lines.filter(Self.isChange).prefix(Metrics.diffLineLimit))
        let changes = lines.filter(Self.isChange).count
        VStack(alignment: .leading, spacing: 0) {
            header
                .font(PiperTheme.paperUI(.body))
                .foregroundStyle(PiperTheme.paperMuted)
                .padding(Metrics.chipPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PiperTheme.rowHover)
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in row(line) }
            if changes > shown.count {
                Text("\(changes - shown.count) more lines")
                    .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
                    .padding(.horizontal, Metrics.diffLineInset).padding(.vertical, Metrics.diffMoreVerticalPadding)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.chipRadius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.chipRadius).strokeBorder(PiperTheme.paperRule, lineWidth: Metrics.edgeWidth))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Changes")
    }

    private static func isChange(_ line: DiffText.Line) -> Bool {
        if case .context = line { return false }
        return true
    }

    private func row(_ line: DiffText.Line) -> some View {
        let (mark, text, fill): (String, String, Color) = {
            switch line {
            case .context(let text): return (" ", text, .clear)
            case .removed(let text): return ("-", text, Metrics.diffRemoved)
            case .added(let text): return ("+", text, Metrics.diffAdded)
            }
        }()
        return Text(mark + " " + text)
            .font(Font(PiperTheme.manuscript(size: Metrics.diffFontSize)))
            .foregroundStyle(PiperTheme.paperInk)
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.diffLineInset).padding(.vertical, Metrics.diffLineVerticalPadding)
            .background(fill)
    }
}

/// A permission request in the transcript, as one line. The request that
/// waits shows in the approval drawer over the composer.
struct PermissionCard: View {
    let request: PermissionRequest
    let decision: PermissionDecision
    let folderName: String

    private var rule: String? { PermissionRule.rule(for: request) }

    /// The text that a call changes, with the path of each file.
    static func diffs(of request: PermissionRequest) -> [(title: String, diff: ToolCall.Diff)] {
        request.diffs.map { (title: $0.path, diff: ToolCall.Diff(old: $0.oldText ?? "", new: $0.newText)) }
    }

    var body: some View {
        if decision == .pending {
            WaitingLine(text: ApprovalDrawer.title(request))
        } else {
            HStack(spacing: TranscriptBlockView.Metrics.lineIconSpacing) {
                Image(systemName: decision == .denied ? "hand.raised" : "lock.open")
                    .foregroundStyle(decision == .denied ? PiperTheme.danger : PiperTheme.paperFaint)
                Text(summary).foregroundStyle(PiperTheme.paperFaint)
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(PiperTheme.paperUI(.body))
        }
    }

    private var summary: String {
        let call = request.detail.isEmpty ? request.toolName : request.toolName + " " + request.detail
        switch decision {
        case .pending: return call
        case .allowed: return "Allowed " + call
        case .allowedAlways: return "Allowed in \(folderName) from now on: " + (rule ?? request.toolName)
        case .denied: return "Denied " + call
        }
    }
}

/// A line in the transcript for a request that waits in the drawer.
struct WaitingLine: View {
    let text: String

    var body: some View {
        HStack(spacing: TranscriptBlockView.Metrics.lineIconSpacing) {
            Image(systemName: "lock.shield").foregroundStyle(PiperTheme.warning)
            Text(text).foregroundStyle(PiperTheme.paperMuted).lineLimit(1)
        }
        .font(PiperTheme.paperUI(.body))
    }
}

/// The questions of a question call.
struct QuestionCard: View {
    let request: PermissionRequest
    let answers: [String: String]?
    let answer: ([String: String]) -> Void
    @State private var chosen: [String: [String]] = [:]

    private var questions: [PermissionRequest.Question] { request.questions }
    private var isComplete: Bool { questions.allSatisfy { chosen[$0.question]?.isEmpty == false } }

    var body: some View {
        if let answers {
            VStack(alignment: .leading, spacing: Metrics.answerSpacing) {
                ForEach(questions, id: \.question) { question in
                    Text(question.question + " " + (answers[question.question] ?? "Not answered"))
                        .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                }
            }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            ForEach(questions, id: \.question) { question in
                VStack(alignment: .leading, spacing: Metrics.questionSpacing) {
                    if !question.header.isEmpty {
                        Text(question.header.uppercased())
                            .font(PiperTheme.paperUI(.body, weight: .semibold)).tracking(Metrics.headerTracking).foregroundStyle(PiperTheme.paperFaint)
                    }
                    Text(question.question).font(PiperTheme.paperUI(.body, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(question.options, id: \.label) { option in
                        optionRow(option, in: question)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Answer") {
                    answer(chosen.mapValues { $0.joined(separator: ", ") })
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isComplete)
            }
            .controlSize(.small)
        }
        .padding(Metrics.cardPadding)
        .background(PiperTheme.paper, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(Metrics.ring, lineWidth: Metrics.ringWidth))
    }

    private func optionRow(_ option: PermissionRequest.Question.Option, in question: PermissionRequest.Question) -> some View {
        let selected = chosen[question.question]?.contains(option.label) == true
        return Button {
            var labels = chosen[question.question] ?? []
            if question.multiSelect {
                if selected { labels.removeAll { $0 == option.label } } else { labels.append(option.label) }
            } else {
                labels = [option.label]
            }
            chosen[question.question] = labels
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.optionSpacing) {
                Image(systemName: question.multiSelect
                      ? (selected ? "checkmark.square.fill" : "square")
                      : (selected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(selected ? PiperTheme.brand : PiperTheme.paperFaint)
                VStack(alignment: .leading, spacing: Metrics.optionTextSpacing) {
                    Text(option.label).font(PiperTheme.paperUI(.body))
                    if !option.description.isEmpty {
                        Text(option.description).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

extension QuestionCard {
    enum Metrics {
        /// The space between the answers of an answered question call.
        static let answerSpacing: CGFloat = 2
        /// The space between the questions of the card.
        static let cardSpacing: CGFloat = 10
        static let questionSpacing: CGFloat = 4
        static let headerTracking: CGFloat = 0.4
        static let cardPadding: CGFloat = 10
        static let ring = PiperTheme.brand.opacity(0.5)
        static let ringWidth: CGFloat = 1
        static let optionSpacing: CGFloat = 6
        /// The space between the label and the description of an option.
        static let optionTextSpacing: CGFloat = 1
    }
}

/// The end of a turn: its time and cost in small faint text, or why it failed.
struct ResultRow: View {
    let result: TurnResult

    private var summary: String {
        var parts = ["Done"]
        if result.durationMs > 0 {
            parts.append(SessionFormat.duration(milliseconds: result.durationMs))
        }
        if result.costUSD > 0 { parts.append(SessionFormat.cost(result.costUSD)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if let failure = result.failure {
            Text(failure)
                .font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.danger)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(summary).font(PiperTheme.paperUI(.body)).foregroundStyle(PiperTheme.paperFaint)
        }
    }
}
