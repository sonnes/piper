import AppKit
import SwiftUI
import Captures
import PiperCore
import Vault

enum WikiReadingTheme: String, CaseIterable {
    case paper = "Paper", sepia = "Sepia", slate = "Slate"

    func background(dark: Bool) -> NSColor {
        switch self {
        case .paper: return PiperTheme.pageNS
        case .sepia: return hex(dark ? 0x29231e : 0xf4edde)
        case .slate: return hex(dark ? 0x1e252d : 0xedf1f5)
        }
    }

    private func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
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

/// Theme, font, size, and appearance for the Wiki page. Shown in the Aa popover and in Settings.
struct ReadingPreferencesView: View {
    @AppStorage("wikiReaderSize") private var fontSize = 18.0
    @AppStorage("wikiReaderTheme") private var theme = WikiReadingTheme.paper
    @AppStorage("wikiReaderFont") private var font = WikiReadingFont.sans
    @AppStorage("wikiReaderAppearance") private var appearance = WikiReadingAppearance.system

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("Paper") {
                Picker("Paper", selection: $theme) {
                    ForEach(WikiReadingTheme.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).accessibilityLabel("Reading Theme")
            }
            row("Font") {
                Picker("Font", selection: $font) {
                    ForEach(WikiReadingFont.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).accessibilityLabel("Reading Font")
            }
            row("Size") {
                HStack(spacing: 0) {
                    Button { fontSize = max(13, fontSize - 1) } label: { Image(systemName: "minus").frame(width: 30, height: 24) }
                        .disabled(fontSize <= 13).accessibilityLabel("Decrease Reading Size")
                    Text("\(Int(fontSize)) pt").font(PiperTheme.ui(11)).monospacedDigit().frame(maxWidth: .infinity)
                    Button { fontSize = min(24, fontSize + 1) } label: { Image(systemName: "plus").frame(width: 30, height: 24) }
                        .disabled(fontSize >= 24).accessibilityLabel("Increase Reading Size")
                }.buttonStyle(.plain)
                    .overlay(RoundedRectangle(cornerRadius: PiperTheme.radius).strokeBorder(PiperTheme.rule, lineWidth: 1))
            }
            row("Appearance") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(WikiReadingAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).accessibilityLabel("Reading Appearance")
            }
            HStack {
                Spacer()
                Button("Reset") { theme = .paper; font = .sans; fontSize = 18; appearance = .system }
                    .buttonStyle(PiperButtonStyle(ghost: true)).help("Reset Reading Preferences")
            }
        }
    }

    private func row<Control: View>(_ title: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            Text(title).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.secondary).frame(width: 72, alignment: .leading)
            control().frame(maxWidth: .infinity)
        }
    }
}

struct WikiInspector: View {
    let model: AppModel
    let document: VaultFile
    let focus: () -> Void
    @State private var tab = Tab.outline
    @State private var confirmDiscard = false

    private enum Tab: String, CaseIterable { case outline = "Outline", links = "Links", info = "Info" }

    private var editable: Bool { FilePresentation(document) == .markdown }
    private var displayedTab: Tab { editable ? tab : .info }
    private var blocks: [WikiBlock] { WikiMarkdown.parse(model.wikiEdit?.markdown ?? document.body) }
    private var headings: [WikiBlock] {
        blocks.enumerated().filter { index, block in
            block.kind == .heading && !(index == 0 && block.level == 1 && block.text == document.title)
        }.map(\.element)
    }
    private var backlinks: [VaultFile] { WikiLinks.backlinks(to: document, in: model.files, vault: model.vault) }
    private var hasChanges: Bool { model.wikiEdit?.hasChanges == true }

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Rule()
            if editable {
                saveRow
                Rule()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch displayedTab {
                    case .outline: outline
                    case .links: links
                    case .info: info
                    }
                }.padding(12)
            }
            .scrollIndicators(.automatic)
        }
        .background(PiperTheme.surface)
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { model.discardWikiEdit() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("The note will return to the version on disk.") }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(editable ? Tab.allCases : [.info], id: \.self) { item in
                let active = item == displayedTab
                Button { tab = item } label: {
                    HStack(spacing: 5) {
                        Text(item.rawValue)
                        if item == .links, !backlinks.isEmpty {
                            Text("\(backlinks.count)").foregroundStyle(PiperTheme.faint).monospacedDigit()
                        }
                    }
                    .font(PiperTheme.ui(11.5, weight: .medium))
                    .foregroundStyle(active ? PiperTheme.ink : PiperTheme.secondary)
                    .padding(.horizontal, 8).frame(height: 38)
                    .overlay(alignment: .bottom) {
                        if active && !PiperTheme.isPage { Rectangle().fill(PiperTheme.accent).frame(height: 2).padding(.horizontal, 8) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.rawValue) tab")
                .accessibilityAddTraits(active ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(height: 38)
    }

    private var saveRow: some View {
        HStack(spacing: 8) {
            Circle().fill(hasChanges ? PiperTheme.warning : PiperTheme.faint).frame(width: 6, height: 6)
            Text(hasChanges ? "Unsaved changes" : "Saved").font(PiperTheme.ui(11.5))
            Spacer(minLength: 0)
            Button("Save ⌘S") { model.saveWikiEdit() }
                .buttonStyle(PiperButtonStyle(prominent: true))
                .disabled(!hasChanges)
                .help("Save Markdown File · ⌘S").accessibilityLabel("Save Markdown File")
        }
        .padding(.horizontal, 14).frame(height: 44)
    }

    private var outline: some View {
        VStack(alignment: .leading, spacing: 2) {
            if headings.isEmpty { emptyText("Headings in this note appear here.") }
            ForEach(headings) { heading in
                let current = model.requestedAnchor == heading.anchor
                Button { model.jump(to: heading.anchor) } label: {
                    Text(WikiMarkdown.inline(heading.text)).lineLimit(2).multilineTextAlignment(.leading)
                        .font(PiperTheme.ui(12))
                        .padding(.leading, CGFloat(max(0, heading.level - 2)) * 12 + 8)
                        .padding(.trailing, 8).padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(current ? PiperTheme.ink : PiperTheme.secondary)
                        .background(current ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var links: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Linked from")
                if backlinks.isEmpty { emptyText("No notes link to this page yet.") }
                ForEach(backlinks) { source in
                    Button { model.openDocument(source.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.title).font(PiperTheme.ui(12)).lineLimit(2)
                            Text(source.folder.isEmpty ? "Wiki" : source.folder).font(PiperTheme.ui(10.5)).foregroundStyle(PiperTheme.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private var info: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("File")
                property("Size", byteFormatter.string(fromByteCount: Int64(document.size)))
                property("Modified", document.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                // Frontmatter is optional. A file that has none shows no rows here.
                ForEach(document.metadata.keys.sorted(), id: \.self) { key in
                    property(key, String(describing: document.metadata[key] ?? ""))
                }
                if let problem = document.problem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(PiperTheme.ui(11))
                        .foregroundStyle(PiperTheme.warning).padding(.horizontal, 8)
                }
                Text(document.id).font(Font(PiperTheme.manuscript(size: 10.5))).foregroundStyle(PiperTheme.secondary).textSelection(.enabled).padding(.horizontal, 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                sectionTitle("Actions")
                if editable {
                    action("Focus", icon: "arrow.up.left.and.arrow.down.right", shortcut: "⌥⌘F", action: focus)
                }
                action("Reveal in Finder", icon: "folder") {
                    guard let url = try? model.vault.containedURL(document.id) else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                if editable {
                    action("Discard Changes…", icon: "arrow.uturn.backward") { confirmDiscard = true }.disabled(!hasChanges)
                }
            }
        }
    }

    private func action(_ title: String, icon: String, shortcut: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(PiperTheme.faint) }
            }
            .font(PiperTheme.ui(12)).padding(.horizontal, 8).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(PiperTheme.ink).help(shortcut.map { "\(title) · \($0)" } ?? title)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased()).font(PiperTheme.ui(10.5, weight: .semibold)).tracking(0.4)
            .foregroundStyle(PiperTheme.secondary).padding(.horizontal, 8).padding(.top, 4)
    }
    private func emptyText(_ text: String) -> some View {
        Text(text).font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary).lineSpacing(3).padding(.horizontal, 8)
    }
    private func property(_ name: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(name).foregroundStyle(PiperTheme.secondary).frame(width: 76, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(PiperTheme.ui(11.5)).padding(.horizontal, 8)
    }
}
