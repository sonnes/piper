import AppKit
import SwiftUI

enum WikiReadingTheme: String, CaseIterable {
    case paper = "Paper", sepia = "Sepia", slate = "Slate"

    func background(dark: Bool) -> NSColor {
        let value: UInt32
        switch self {
        case .paper: value = dark ? 0x18191A : 0xFCFCFA
        case .sepia: value = dark ? 0x29231e : 0xf4edde
        case .slate: value = dark ? 0x1e252d : 0xedf1f5
        }
        return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                       green: CGFloat((value >> 8) & 255) / 255,
                       blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}

enum WikiReadingFont: String, CaseIterable {
    case mono = "Monospace", serif = "Serif", sans = "Sans Serif"

    func font(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        switch self {
        case .mono: return PiperTheme.manuscript(size: size, weight: weight)
        case .sans: return .systemFont(ofSize: size, weight: weight)
        case .serif:
            let system = NSFont.systemFont(ofSize: size, weight: weight)
            guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
            return NSFont(descriptor: descriptor, size: size) ?? system
        }
    }
}

enum WikiReadingAppearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}

struct WikiInspector: View {
    let model: AppModel
    let document: WikiDocument
    @Binding var theme: WikiReadingTheme
    @Binding var font: WikiReadingFont
    @Binding var fontSize: Double
    @Binding var appearance: WikiReadingAppearance
    let focus: () -> Void
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var showOutline = true
    @State private var showBacklinks = false
    @State private var showProperties = false
    @State private var showSources = false
    @State private var confirmDiscard = false

    private var blocks: [WikiBlock] { WikiMarkdown.parse(model.wikiEdit?.markdown ?? document.body) }
    private var headings: [WikiBlock] {
        blocks.enumerated().filter { index, block in
            block.kind == .heading && !(index == 0 && block.level == 1 && block.text == document.title)
        }.map(\.element)
    }
    private var backlinks: [WikiDocument] { WikiLinks.backlinks(to: document, in: model.documents, repository: model.repository) }
    private var paper: Color { Color(nsColor: theme.background(dark: colorScheme == .dark)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text").font(.system(size: 14, weight: .medium)).foregroundStyle(PiperTheme.secondary)
                Text("Document").font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: close) { Image(systemName: "sidebar.right").font(.system(size: 13)).frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(PiperTheme.secondary).help("Hide Document Sidebar").accessibilityLabel("Hide Document Sidebar")
            }.padding(.horizontal, 16).frame(height: 48)
            Divider()
            saveControls
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    preview.padding(.top, 22).padding(.bottom, 24)
                    sectionTitle("Theme")
                    themePicker.padding(.top, 10)
                    separator
                    typography
                    separator
                    sectionTitle("Appearance")
                    Picker("Appearance", selection: $appearance) {
                        ForEach(WikiReadingAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented).labelsHidden().controlSize(.small).padding(.top, 11)
                        .accessibilityLabel("Reading Appearance")
                    separator
                    DisclosureGroup(isExpanded: $showOutline) {
                        outline.padding(.top, 8)
                    } label: { disclosureTitle("On This Page", count: headings.count) }
                    separator
                    DisclosureGroup(isExpanded: $showBacklinks) {
                        backlinkList.padding(.top, 12)
                    } label: { disclosureTitle("Backlinks", count: backlinks.count) }
                    separator
                    DisclosureGroup(isExpanded: $showProperties) {
                        properties.padding(.top, 14)
                    } label: { sectionTitle("Note Details") }
                    if !document.sources.isEmpty {
                        separator
                        DisclosureGroup(isExpanded: $showSources) {
                            sources.padding(.top, 12)
                        } label: { disclosureTitle("Sources", count: document.sources.count) }
                    }
                    separator
                    documentActions
                }.padding(.horizontal, 18).padding(.bottom, 24)
            }
            .scrollIndicators(.automatic)
            .contentMargins(.trailing, 3, for: .scrollIndicators)
            .contentMargins(.vertical, 10, for: .scrollIndicators)
            Divider()
            HStack {
                Text("Reading preferences").foregroundStyle(PiperTheme.secondary)
                Spacer()
                Button("Reset") { theme = .paper; font = .mono; fontSize = 18; appearance = .system }
                    .buttonStyle(.plain).foregroundStyle(PiperTheme.secondary)
                    .help("Reset Reading Preferences").accessibilityLabel("Reset Reading Preferences")
            }.font(.system(size: 10)).padding(.horizontal, 18).frame(height: 38)
        }
        .background(WikiStyle.sidebar)
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { model.discardWikiEdit() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("The note will return to the version on disk.") }
        .onChange(of: document.id) { _, _ in showProperties = false; showSources = false }
    }

    private var saveControls: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(model.wikiEdit?.hasChanges == true ? Color.orange : PiperTheme.secondary.opacity(0.45)).frame(width: 5, height: 5)
                    Text(model.wikiEdit?.hasChanges == true ? "Unsaved changes" : "Saved").font(.system(size: 11, weight: .medium))
                }
                Text("Manual save").font(.system(size: 10)).foregroundStyle(PiperTheme.secondary)
            }
            Spacer(minLength: 0)
            Button { model.saveWikiEdit() } label: {
                HStack(spacing: 9) {
                    Text("Save").fontWeight(.medium)
                    Text("⌘S").opacity(0.65)
                }.font(.system(size: 11)).padding(.horizontal, 5).padding(.vertical, 3)
            }.buttonStyle(.borderedProminent).foregroundStyle(PiperTheme.page).controlSize(.small)
                .disabled(model.wikiEdit?.hasChanges != true)
                .help("Save Markdown File · ⌘S").accessibilityLabel("Save Markdown File")
        }.padding(.horizontal, 18).frame(height: 66)
    }

    private var documentActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("Actions")
            Button(action: focus) {
                HStack {
                    Label("Focus", systemImage: "arrow.up.left.and.arrow.down.right")
                    Spacer()
                    Text("⌥⌘F").foregroundStyle(PiperTheme.secondary)
                }
            }.help("Focus · ⌥⌘F")
            Button {
                guard let url = try? model.repository.containedURL(document.id) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: { Label("Reveal in Finder", systemImage: "folder") }
            Button { confirmDiscard = true } label: { Label("Discard Changes…", systemImage: "arrow.uturn.backward") }
                .disabled(model.wikiEdit?.hasChanges != true)
        }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(PiperTheme.secondary)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(document.title).font(Font(font.font(size: 12, weight: .semibold))).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let paragraph = blocks.first(where: { $0.kind == .paragraph || $0.kind == .listItem || $0.kind == .quote }) {
                Text(WikiMarkdown.inline(paragraph.text)).font(Font(font.font(size: fontSize * 0.47)))
                    .lineSpacing(3).lineLimit(4).foregroundStyle(PiperTheme.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer(minLength: 0)
            Rectangle().fill(.primary.opacity(0.15)).frame(width: 22, height: 1)
        }
        .padding(20).frame(maxWidth: .infinity).frame(height: 142)
        .background(paper, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.09), lineWidth: 0.5))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.12 : 0.06), radius: 7, y: 3)
        .accessibilityElement(children: .ignore).accessibilityLabel("Reading preview: \(document.title)")
    }

    private var themePicker: some View {
        Menu {
            Picker("Theme", selection: $theme) {
                ForEach(WikiReadingTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
        } label: {
            HStack(spacing: 10) {
                Text("Aa").font(Font(font.font(size: 11, weight: .medium)))
                    .frame(width: 34, height: 23).background(paper, in: RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
                Text(theme.rawValue).font(.system(size: 12))
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .medium)).foregroundStyle(PiperTheme.secondary)
            }.padding(.horizontal, 8).frame(height: 34)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 3))
                .contentShape(RoundedRectangle(cornerRadius: 3))
        }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Reading Theme").accessibilityValue(theme.rawValue)
    }

    private var typography: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionTitle("Typography")
            HStack(spacing: 12) {
                Text("Font").foregroundStyle(PiperTheme.secondary).frame(width: 48, alignment: .trailing)
                Picker("Font", selection: $font) {
                    ForEach(WikiReadingFont.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.labelsHidden().controlSize(.small).frame(maxWidth: .infinity)
                    .accessibilityLabel("Reading Font")
            }
            HStack(spacing: 12) {
                Text("Size").foregroundStyle(PiperTheme.secondary).frame(width: 48, alignment: .trailing)
                HStack(spacing: 0) {
                    Button { fontSize = max(13, fontSize - 1) } label: { Image(systemName: "minus").frame(width: 30, height: 26) }
                        .disabled(fontSize <= 13).accessibilityLabel("Decrease Reading Size")
                    Text("\(Int(fontSize)) pt").monospacedDigit().frame(maxWidth: .infinity)
                    Button { fontSize = min(24, fontSize + 1) } label: { Image(systemName: "plus").frame(width: 30, height: 26) }
                        .disabled(fontSize >= 24).accessibilityLabel("Increase Reading Size")
                }.buttonStyle(.plain).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 5))
            }
        }.font(.system(size: 11))
    }

    private var outline: some View {
        VStack(alignment: .leading, spacing: 2) {
            if headings.isEmpty { emptyText("Headings in this note appear here.") }
            ForEach(headings) { heading in
                Button { model.jump(to: heading.anchor) } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 1).fill(model.requestedAnchor == heading.anchor ? PiperTheme.accent : .clear).frame(width: 2)
                        Text(WikiMarkdown.inline(heading.text)).lineLimit(2).multilineTextAlignment(.leading)
                            .padding(.leading, CGFloat(max(0, heading.level - 2)) * 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.system(size: 11)).padding(.vertical, 6).padding(.trailing, 6)
                        .foregroundStyle(model.requestedAnchor == heading.anchor ? PiperTheme.ink : PiperTheme.secondary)
                        .background(model.requestedAnchor == heading.anchor ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 3))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var backlinkList: some View {
        VStack(alignment: .leading, spacing: 12) {
            if backlinks.isEmpty { emptyText("No notes link to this page yet.") }
            ForEach(backlinks) { source in
                Button { model.openDocument(source.id) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(source.title, systemImage: "doc.text").font(.system(size: 11)).lineLimit(2)
                        Text(source.folder.isEmpty ? "Wiki" : source.folder).font(.system(size: 10)).foregroundStyle(PiperTheme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var properties: some View {
        VStack(alignment: .leading, spacing: 12) {
            property("Type", document.type)
            if !document.status.isEmpty { property("Status", document.status.capitalized) }
            property("Review", document.verification)
            if document.isStale { Label("Review overdue", systemImage: "clock").font(.system(size: 11)).foregroundStyle(.orange) }
            if let generated = document.metadata["generated"] as? [String: Any], let by = generated["by"] as? String { property("Generated by", by) }
            Text(document.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(PiperTheme.secondary).textSelection(.enabled)
        }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(document.sources.enumerated()), id: \.offset) { _, source in
                if let resource = source["resource"] as? String, let url = URL(string: resource) {
                    Button { model.openLink(url, from: document) } label: {
                        Label(source["title"] as? String ?? resource, systemImage: "arrow.up.right")
                            .font(.system(size: 11)).lineLimit(3).multilineTextAlignment(.leading)
                    }.buttonStyle(.plain).foregroundStyle(PiperTheme.accent)
                }
            }
        }
    }

    private var separator: some View { Divider().overlay(WikiStyle.hairline).padding(.vertical, 18) }
    private func sectionTitle(_ title: String) -> some View { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(PiperTheme.ink) }
    private func disclosureTitle(_ title: String, count: Int) -> some View {
        HStack {
            sectionTitle(title)
            Spacer()
            Text("\(count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(PiperTheme.secondary)
        }
    }
    private func emptyText(_ text: String) -> some View { Text(text).font(.system(size: 11)).foregroundStyle(PiperTheme.secondary).lineSpacing(3) }
    private func property(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(name).foregroundStyle(PiperTheme.secondary).frame(width: 54, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.system(size: 11))
    }
}
