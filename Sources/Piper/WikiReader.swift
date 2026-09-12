import AppKit
import SwiftUI

struct WikiReader: View {
    let model: AppModel
    let document: WikiDocument
    let showSource: Bool
    let fontSize: Double
    var paper = WikiStyle.paper

    private var blocks: [WikiBlock] { WikiMarkdown.parse(document.body) }
    private var displayBlocks: [WikiBlock] {
        if blocks.first?.kind == .heading, blocks.first?.level == 1 { return Array(blocks.dropFirst()) }
        return blocks
    }
    private var heading: String { blocks.first?.kind == .heading && blocks.first?.level == 1 ? blocks[0].text : document.title }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 1).id("top")
                        if showSource {
                            Text(document.raw).font(Font(PiperTheme.manuscript(size: fontSize - 3))).lineSpacing(7)
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        } else {
                            VStack(alignment: .leading, spacing: 15) {
                                Text(WikiMarkdown.inline(heading)).font(Font(PiperTheme.manuscript(size: fontSize * 1.34, weight: .medium))).tracking(-0.8)
                                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                if !document.description.isEmpty {
                                    Text(document.description).font(.system(size: 14)).foregroundStyle(PiperTheme.secondary).lineSpacing(5)
                                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                }
                            }.padding(.bottom, 35)
                            if let problem = document.problem {
                                Label(problem, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange).padding(.bottom, 24)
                            }
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(displayBlocks.enumerated()), id: \.element.id) { index, block in
                                    WikiBlockView(block: block, fontSize: fontSize)
                                        .padding(.top, spacing(before: block, at: index))
                                        .id(block.anchor.isEmpty ? "block-\(block.id)" : block.anchor)
                                }
                            }
                            HStack(spacing: 8) {
                                Rectangle().fill(WikiStyle.hairline).frame(width: 28, height: 1)
                                Image(systemName: "circle.fill").font(.system(size: 3)).foregroundStyle(PiperTheme.secondary)
                                Rectangle().fill(WikiStyle.hairline).frame(width: 28, height: 1)
                            }.frame(maxWidth: .infinity).padding(.top, 52)
                        }
                    }
                    .frame(maxWidth: 650, alignment: .leading)
                    .padding(.horizontal, 44).padding(.top, 34).padding(.bottom, 84)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.automatic)
                .contentMargins(.trailing, 5, for: .scrollIndicators)
                .contentMargins(.vertical, 12, for: .scrollIndicators)
                .onChange(of: model.anchorRequest) { _, _ in scroll(proxy) }
                .onChange(of: showSource) { _, _ in scroll(proxy) }
                .onAppear { scroll(proxy) }
            }.id(document.id)
        }
        .background(paper)
        .environment(\.openURL, OpenURLAction { url in model.openLink(url, from: document); return .handled })
    }

    private func spacing(before block: WikiBlock, at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        if block.kind == .heading { return 34 }
        if block.kind == .listItem && displayBlocks[index - 1].kind == .listItem { return 7 }
        if block.kind == .footnote { return 12 }
        return 20
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard model.selectedDocument == document.id else { return }
        guard !showSource, let requested = model.requestedAnchor, !requested.isEmpty else { proxy.scrollTo("top", anchor: .top); return }
        let anchor = blocks.first { $0.anchor == requested || $0.anchor == WikiMarkdown.anchor(requested) }?.anchor
        if let anchor {
            if blocks.first?.anchor == anchor { proxy.scrollTo("top", anchor: .top) }
            else { proxy.scrollTo(anchor, anchor: .top) }
        } else { model.store.report(PiperError("The heading “\(requested)” is unavailable in this note.")) }
    }
}

private struct WikiBlockView: View {
    let block: WikiBlock
    let fontSize: Double
    @State private var copied = false
    private var proseFont: Font { Font(PiperTheme.manuscript(size: fontSize)) }

    @ViewBuilder var body: some View {
        switch block.kind {
        case .heading:
            Text(WikiMarkdown.inline(block.text))
                .font(Font(PiperTheme.manuscript(size: block.level == 1 ? fontSize * 1.34 : block.level == 2 ? fontSize * 1.12 : fontSize, weight: .medium)))
                .tracking(-0.3).textSelection(.enabled).accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .paragraph:
            prose(block.text)
        case .listItem:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(block.marker).font(proseFont).foregroundStyle(PiperTheme.secondary).frame(minWidth: 19, alignment: .trailing)
                prose(block.text)
            }.padding(.leading, CGFloat(min(block.level, 6)) * 20)
        case .quote:
            HStack(alignment: .top, spacing: 17) {
                RoundedRectangle(cornerRadius: 1).fill(PiperTheme.accent.opacity(0.45)).frame(width: 2)
                prose(block.text).foregroundStyle(PiperTheme.secondary)
            }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 3)
        case .code:
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(block.marker.isEmpty ? "Code" : block.marker).font(.system(size: 10, weight: .medium))
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(block.text, forType: .string)
                        copied = true
                    } label: { Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10)) }
                        .buttonStyle(.plain).accessibilityLabel("Copy Code")
                }.foregroundStyle(PiperTheme.secondary).padding(.horizontal, 16).padding(.vertical, 11)
                Divider().opacity(0.5)
                ScrollView(.horizontal) {
                    Text(block.text).font(Font(PiperTheme.manuscript(size: fontSize - 3))).lineSpacing(6)
                        .textSelection(.enabled).fixedSize(horizontal: true, vertical: false).padding(16)
                }.scrollIndicators(.automatic)
            }.background(PiperTheme.surface, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(WikiStyle.hairline, lineWidth: 1))
        case .table:
            table
        case .rule:
            Divider().padding(.vertical, 5)
        case .footnote:
            HStack(alignment: .top, spacing: 10) {
                Text(block.marker).font(.system(size: 10, weight: .medium)).foregroundStyle(PiperTheme.accent)
                Text(WikiMarkdown.inline(block.text)).font(.system(size: 12)).lineSpacing(5).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.foregroundStyle(PiperTheme.secondary)
        }
    }

    private func prose(_ text: String) -> some View {
        Text(WikiMarkdown.inline(text)).font(proseFont).lineSpacing(fontSize * 0.3)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var table: some View {
        let rows = block.text.components(separatedBy: "\n").enumerated().filter { $0.offset != 1 }.map {
            $0.element.trimmingCharacters(in: CharacterSet(charactersIn: " |"))
                .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 13) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, cells in
                    GridRow {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                            Text(WikiMarkdown.inline(cell)).font(.system(size: 12, weight: index == 0 ? .semibold : .regular))
                                .lineSpacing(4).frame(minWidth: 95, maxWidth: 250, alignment: .leading).textSelection(.enabled)
                        }
                    }
                    if index < rows.count - 1 { Divider().gridCellUnsizedAxes(.horizontal) }
                }
            }.padding(16)
        }.background(PiperTheme.surface, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(WikiStyle.hairline, lineWidth: 1))
    }
}

