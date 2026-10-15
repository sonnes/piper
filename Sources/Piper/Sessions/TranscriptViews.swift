import Agents
import AppKit
import SwiftUI

/// One block of a transcript.
struct TranscriptBlockView: View {
    let model: AppModel
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
                model.openRunFile(path, in: session.folder)
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

/// A message from the reader, as a bubble on the right, with the files it
/// named as context under it.
struct UserTurnView: View {
    let text: String
    let context: [String]

    private typealias Metrics = AppDefaults.Sessions

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(text)
                .font(PiperTheme.ui(13))
                .lineSpacing(3)
                .foregroundStyle(PiperTheme.onAccent)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(Metrics.bubblePadding)
                .background(PiperTheme.accent, in: UnevenRoundedRectangle(
                    topLeadingRadius: Metrics.bubbleRadius, bottomLeadingRadius: Metrics.bubbleRadius,
                    bottomTrailingRadius: Metrics.bubbleTailRadius, topTrailingRadius: Metrics.bubbleRadius))
            ForEach(context, id: \.self) { path in
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc.text")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint)
                    .help(path)
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
            .font(PiperTheme.ui(13))
            .lineSpacing(3.5)
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

    private typealias Metrics = AppDefaults.Sessions

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let diff = call.diff {
                DiffView(diff: diff) { header }
            } else {
                header
                    .padding(Metrics.chipPadding)
                    .background(PiperTheme.hover, in: RoundedRectangle(cornerRadius: Metrics.chipRadius))
            }
            if expanded, let preview = call.resultPreview {
                Text(preview)
                    .font(Font(PiperTheme.manuscript(size: 11)))
                    .foregroundStyle(call.isError ? PiperTheme.danger : PiperTheme.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Metrics.chipPadding)
                    .overlay(RoundedRectangle(cornerRadius: Metrics.chipRadius).strokeBorder(PiperTheme.rule, lineWidth: 1))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(call.line)
    }

    private var header: some View {
        HStack(spacing: 7) {
            status.frame(width: 12)
            Text(call.line)
                .font(Font(PiperTheme.manuscript(size: 12)))
                .foregroundStyle(PiperTheme.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if let path = call.path, path.lowercased().hasSuffix(".md"), !call.isError {
                Button("Open") { open(path) }.buttonStyle(.link).font(PiperTheme.ui(11))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if call.resultPreview != nil { expanded.toggle() } }
    }

    @ViewBuilder private var status: some View {
        if call.isError {
            Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(PiperTheme.danger)
        } else if call.isFinished {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(PiperTheme.toolDone)
        } else if isLive {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(PiperTheme.faint)
        }
    }
}

/// The lines that an edit removes and adds, in a card with a header row.
struct DiffView<Header: View>: View {
    let diff: ToolCall.Diff
    @ViewBuilder let header: Header

    private typealias Metrics = AppDefaults.Sessions
    private var lines: [DiffText.Line] { DiffText.lines(old: diff.old, new: diff.new) }

    var body: some View {
        let shown = Array(lines.filter(Self.isChange).prefix(Metrics.diffLineLimit))
        let changes = lines.filter(Self.isChange).count
        VStack(alignment: .leading, spacing: 0) {
            header
                .font(PiperTheme.ui(11.5))
                .foregroundStyle(PiperTheme.secondary)
                .padding(Metrics.chipPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(PiperTheme.hover)
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in row(line) }
            if changes > shown.count {
                Text("\(changes - shown.count) more lines")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint)
                    .padding(.horizontal, 9).padding(.vertical, 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.chipRadius))
        .overlay(RoundedRectangle(cornerRadius: Metrics.chipRadius).strokeBorder(PiperTheme.rule, lineWidth: 1))
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
            case .removed(let text): return ("-", text, PiperTheme.diffRemoved)
            case .added(let text): return ("+", text, PiperTheme.diffAdded)
            }
        }()
        return Text(mark + " " + text)
            .font(Font(PiperTheme.manuscript(size: 11.5)))
            .foregroundStyle(PiperTheme.ink)
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 9).padding(.vertical, 1)
            .background(fill)
    }
}

extension DiffView where Header == EmptyView {
    init(diff: ToolCall.Diff) {
        self.init(diff: diff) { EmptyView() }
    }
}

/// A permission request in the transcript, as one line. The request that
/// waits shows in the approval drawer over the composer.
struct PermissionCard: View {
    let request: PermissionRequest
    let decision: PermissionDecision
    let folderName: String

    private var rule: String? { PermissionRule.rule(toolName: request.toolName, input: request.input) }

    /// The text that a call changes, with the path of each file. An ACP agent
    /// gives its diffs. For Claude Code, the diff comes from the input of
    /// Edit or Write, and the title is empty.
    static func diffs(of request: PermissionRequest) -> [(title: String, diff: ToolCall.Diff)] {
        if let diffs = request.diffs, !diffs.isEmpty {
            return diffs.map { (title: $0.path, diff: ToolCall.Diff(old: $0.oldText ?? "", new: $0.newText)) }
        }
        if request.toolName == "Edit", let old = request.input["old_string"]?.string,
           let new = request.input["new_string"]?.string { return [(title: "", diff: ToolCall.Diff(old: old, new: new))] }
        if request.toolName == "Write", let content = request.input["content"]?.string {
            return [(title: "", diff: ToolCall.Diff(old: "", new: content))]
        }
        return []
    }

    var body: some View {
        if decision == .pending {
            WaitingLine(text: ApprovalDrawer.title(request))
        } else {
            HStack(spacing: 6) {
                Image(systemName: decision == .denied ? "hand.raised" : "lock.open")
                    .foregroundStyle(decision == .denied ? PiperTheme.danger : PiperTheme.faint)
                Text(summary).foregroundStyle(PiperTheme.faint)
                    .lineLimit(1).truncationMode(.middle)
            }
            .font(PiperTheme.ui(11))
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
        HStack(spacing: 6) {
            Image(systemName: "lock.shield").foregroundStyle(PiperTheme.warning)
            Text(text).foregroundStyle(PiperTheme.secondary).lineLimit(1)
        }
        .font(PiperTheme.ui(11))
    }
}

/// The questions of an `AskUserQuestion` call.
struct QuestionCard: View {
    let request: PermissionRequest
    let answers: [String: String]?
    let answer: ([String: String]) -> Void
    @State private var chosen: [String: [String]] = [:]

    private var questions: [PermissionRequest.Question] { request.questions }
    private var isComplete: Bool { questions.allSatisfy { chosen[$0.question]?.isEmpty == false } }

    var body: some View {
        if let answers {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(questions, id: \.question) { question in
                    Text(question.question + " " + (answers[question.question] ?? "Not answered"))
                        .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                }
            }
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(questions, id: \.question) { question in
                VStack(alignment: .leading, spacing: 4) {
                    if !question.header.isEmpty {
                        Text(question.header.uppercased())
                            .font(PiperTheme.ui(10.5, weight: .semibold)).tracking(0.4).foregroundStyle(PiperTheme.faint)
                    }
                    Text(question.question).font(PiperTheme.ui(13, weight: .semibold))
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
        .padding(10)
        .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.accent.opacity(0.5), lineWidth: 1))
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
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: question.multiSelect
                      ? (selected ? "checkmark.square.fill" : "square")
                      : (selected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(selected ? PiperTheme.accent : PiperTheme.faint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(option.label).font(PiperTheme.ui(13))
                    if !option.description.isEmpty {
                        Text(option.description).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
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

/// The end of a turn: its time and cost in small faint text, or why it failed.
struct ResultRow: View {
    let result: TurnResult

    private var summary: String {
        var parts = ["Done"]
        if result.durationMs > 0 {
            parts.append(Duration.milliseconds(result.durationMs)
                .formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated, fractionalPart: .hide)))
        }
        if result.costUSD > 0 { parts.append(String(format: "$%.2f", result.costUSD)) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        if let failure = result.failure {
            Text(failure)
                .font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.danger)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(summary).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint)
        }
    }
}
