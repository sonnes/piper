import Agents
import AppKit
import SwiftUI

/// One block of a transcript.
struct TranscriptBlockView: View {
    let model: AppModel
    let session: AgentSession
    let block: TranscriptBlock

    private var runner: SessionRunner { model.agents.runner }

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
            PermissionCard(request: request, decision: decision, folderName: session.folderName,
                           allow: { always in runner.allow(request, always: always, in: session) },
                           deny: { runner.deny(request, in: session) })
        case .question(let request, let answers):
            QuestionCard(request: request, answers: answers) { runner.answer(request, answers: $0, in: session) }
        case .result(_, let result):
            ResultRow(result: result)
        }
    }
}

/// A message from the reader, with the files it named as context.
struct UserTurnView: View {
    let text: String
    let context: [String]

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(text)
                .font(PiperTheme.ui(13))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(PiperTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
            ForEach(context, id: \.self) { path in
                Label(URL(fileURLWithPath: path).lastPathComponent, systemImage: "doc.text")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary)
                    .help(path)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 24)
    }
}

/// A message from Claude. Inline Markdown shows as formatted text.
struct AssistantTextView: View {
    let text: String

    private var formatted: AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }

    var body: some View {
        Text(formatted)
            .font(PiperTheme.ui(13))
            .lineSpacing(2)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One tool call. A click shows the start of its result.
struct ToolCallRow: View {
    let call: ToolCall
    /// True while the session can still finish the call.
    let isLive: Bool
    let open: (String) -> Void
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                status.frame(width: 14)
                Text(call.name).font(PiperTheme.ui(12, weight: .semibold))
                Text(call.detail)
                    .font(Font(PiperTheme.manuscript(size: 11.5)))
                    .foregroundStyle(PiperTheme.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                if let path = call.path, path.lowercased().hasSuffix(".md"), !call.isError {
                    Button("Open") { open(path) }.buttonStyle(.link).font(PiperTheme.ui(11))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if call.resultPreview != nil { expanded.toggle() } }
            if let diff = call.diff { DiffView(diff: diff) }
            if expanded, let preview = call.resultPreview {
                Text(preview)
                    .font(Font(PiperTheme.manuscript(size: 11)))
                    .foregroundStyle(call.isError ? PiperTheme.danger : PiperTheme.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(PiperTheme.panel, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(call.line)
    }

    @ViewBuilder private var status: some View {
        if call.isError {
            Image(systemName: "xmark.circle").foregroundStyle(PiperTheme.danger)
        } else if call.isFinished {
            Image(systemName: "checkmark").foregroundStyle(PiperTheme.faint)
        } else if isLive {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "circle.dashed").foregroundStyle(PiperTheme.faint)
        }
    }
}

/// The lines that an Edit call removes and adds.
struct DiffView: View {
    let diff: ToolCall.Diff

    private var lines: [DiffText.Line] { DiffText.lines(old: diff.old, new: diff.new) }

    var body: some View {
        let shown = Array(lines.prefix(AppDefaults.Sessions.diffLineLimit))
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, line in row(line) }
            if lines.count > shown.count {
                Text("\(lines.count - shown.count) more lines")
                    .font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint).padding(.horizontal, 6).padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .background(PiperTheme.panel, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
        .accessibilityLabel("Changes")
    }

    private func row(_ line: DiffText.Line) -> some View {
        let (mark, text, color): (String, String, Color?) = {
            switch line {
            case .context(let text): return (" ", text, nil)
            case .removed(let text): return ("-", text, PiperTheme.danger)
            case .added(let text): return ("+", text, PiperTheme.success)
            }
        }()
        return Text(mark + " " + text)
            .font(Font(PiperTheme.manuscript(size: 11)))
            .foregroundStyle(color ?? PiperTheme.secondary)
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .background((color ?? .clear).opacity(0.1))
    }
}

/// A tool call that waits for the reader to allow or deny it.
struct PermissionCard: View {
    let request: PermissionRequest
    let decision: PermissionDecision
    let folderName: String
    let allow: (_ always: Bool) -> Void
    let deny: () -> Void

    private var rule: String? { PermissionRule.rule(toolName: request.toolName, input: request.input) }

    private var diff: ToolCall.Diff? {
        if request.toolName == "Edit", let old = request.input["old_string"]?.string,
           let new = request.input["new_string"]?.string { return ToolCall.Diff(old: old, new: new) }
        if request.toolName == "Write", let content = request.input["content"]?.string {
            return ToolCall.Diff(old: "", new: content)
        }
        return nil
    }

    var body: some View {
        if decision == .pending {
            card
        } else {
            HStack(spacing: 6) {
                Image(systemName: decision == .denied ? "hand.raised" : "lock.open")
                    .foregroundStyle(decision == .denied ? PiperTheme.danger : PiperTheme.secondary)
                Text(summary).font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
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

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "lock").foregroundStyle(PiperTheme.warning)
                Text("Allow \(request.toolName)?").font(PiperTheme.ui(13, weight: .semibold))
            }
            if !request.detail.isEmpty {
                Text(request.detail)
                    .font(Font(PiperTheme.manuscript(size: 11.5)))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let diff { DiffView(diff: diff) }
            HStack(spacing: 6) {
                Button("Deny", action: deny)
                Spacer(minLength: 0)
                if let rule {
                    Button("Always in \(folderName)") { allow(true) }
                        .help("Adds \(rule) to .claude/settings.local.json in \(folderName)")
                }
                Button("Allow Once") { allow(false) }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(PiperTheme.card, in: RoundedRectangle(cornerRadius: PiperTheme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: PiperTheme.cardRadius).strokeBorder(PiperTheme.warning.opacity(0.6), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude asks to use \(request.toolName)")
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

/// The end of a turn: its time and cost, or why it failed.
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
            HStack(spacing: 6) {
                Rule().frame(width: 16)
                Text(summary).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.faint)
                Rule()
            }
        }
    }
}
