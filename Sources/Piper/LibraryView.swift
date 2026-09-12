import AppKit
import SwiftUI
import ApplicationServices

struct ExportView: View {
    @Bindable var model: AppModel
    @State private var title = ""
    @State private var description = ""
    @State private var destination = "sources"
    @State private var sourceURL = ""
    @State private var error: String?
    @State private var saved = false
    @Environment(\.dismiss) private var dismiss

    private var canSave: Bool {
        !model.exporting && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if saved {
                Text("Draft saved").font(PiperTheme.ui(13, weight: .semibold))
                Text(title).font(PiperTheme.ui(13))
                Text(model.selectedDocument ?? "").font(Font(PiperTheme.manuscript(size: 11))).foregroundStyle(PiperTheme.secondary).textSelection(.enabled)
                Text("Captures stay in Piper. The draft is unverified.").font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary).padding(.top, 4)
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(PiperButtonStyle())
                    Button("Read in Wiki") { dismiss(); model.openLibrary?() }.buttonStyle(PiperButtonStyle(prominent: true))
                }.padding(.top, 8)
            } else {
                HStack(spacing: 6) {
                    Text("Send to Wiki").font(PiperTheme.ui(13, weight: .semibold))
                    Text("· \(model.exportNotes.count) captures · one draft").font(PiperTheme.ui(12)).foregroundStyle(PiperTheme.secondary)
                }.padding(.bottom, 4)
                PiperField(title: "Title", text: $title)
                PiperField(title: "Description", text: $description, lines: 1...4)
                Picker("Destination", selection: $destination) {
                    ForEach(WikiRepository.destinations, id: \.self) { Text($0.capitalized).tag($0) }
                }.pickerStyle(.segmented).labelsHidden().controlSize(.small).accessibilityLabel("Destination")
                PiperField(title: "Source URL", text: $sourceURL, hint: "optional")
                Text("\(destination)/\(WikiRepository.slug(title)).md").font(Font(PiperTheme.manuscript(size: 11))).foregroundStyle(PiperTheme.secondary)
                ScrollView {
                    Text(model.exportNotes.map(\.text).joined(separator: "\n\n"))
                        .font(Font(PiperTheme.manuscript(size: 12))).lineSpacing(4).foregroundStyle(PiperTheme.secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10)
                }
                .frame(height: 120)
                .overlay(RoundedRectangle(cornerRadius: PiperTheme.radius).strokeBorder(PiperTheme.rule, lineWidth: 1))
                if let error { Text(error).font(PiperTheme.ui(11)).foregroundStyle(PiperTheme.danger).textSelection(.enabled) }
                HStack {
                    Spacer()
                    if model.exporting { ProgressView().controlSize(.small) }
                    Button("Cancel") { dismiss() }.buttonStyle(PiperButtonStyle()).keyboardShortcut(.cancelAction).disabled(model.exporting)
                    Button("Save Draft") {
                        Task {
                            error = await model.export(title: title, description: description, destination: destination, sourceURL: sourceURL)
                            saved = error == nil
                        }
                    }.buttonStyle(PiperButtonStyle(prominent: true)).disabled(!canSave)
                }.padding(.top, 6)
            }
        }
        .padding(22).frame(width: 480)
        .background(PiperTheme.page).foregroundStyle(PiperTheme.ink)
        .interactiveDismissDisabled(model.exporting)
        .onAppear {
            let first = model.exportNotes.first?.text.components(separatedBy: .newlines).first ?? ""
            title = String(first.prefix(80))
            sourceURL = model.exportNotes.flatMap(\.sourceURLs).first ?? ""
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var section = Section.wiki
    @Environment(\.dismiss) private var dismiss
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private enum Section: String, CaseIterable { case wiki = "Wiki", capture = "Capture", reading = "Reading", style = "Style", data = "Local Data" }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("SETTINGS").font(PiperTheme.ui(10.5, weight: .semibold)).tracking(0.4).foregroundStyle(PiperTheme.secondary)
                    .padding(.horizontal, 10).padding(.bottom, 6)
                ForEach(Section.allCases, id: \.self) { item in
                    Button { section = item } label: {
                        Text(item.rawValue).font(PiperTheme.ui(12.5, weight: item == section ? .medium : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(item == section ? PiperTheme.selection : .clear, in: RoundedRectangle(cornerRadius: PiperTheme.radius))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(10).padding(.top, 10).frame(width: 180)
            .background(PiperTheme.surface)
            Rule(vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(section.rawValue).font(PiperTheme.ui(15, weight: .semibold))
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(PiperButtonStyle()).keyboardShortcut(.cancelAction)
                }.padding(.bottom, 8)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch section {
                        case .wiki: wiki
                        case .capture: capture
                        case .reading: reading
                        case .style: style
                        case .data: data
                        }
                    }
                }
            }
            .padding(22)
        }
        .frame(width: 760, height: 500)
        .background(PiperTheme.page).foregroundStyle(PiperTheme.ink)
        .tint(PiperTheme.accent).accentColor(PiperTheme.accent)
        .onReceive(timer) { _ in model.accessibilityEnabled = AXIsProcessTrusted() }
    }

    private var wiki: some View {
        Group {
            item("Folder", (model.wikiPath as NSString).abbreviatingWithTildeInPath) {
                Button("Change") { model.chooseWiki() }.buttonStyle(PiperButtonStyle())
            }
            item("Exports", "Send to Wiki creates unverified drafts. Existing concepts stay unchanged.") { EmptyView() }
        }
    }

    private var capture: some View {
        Group {
            item("Shortcut", "Press it to capture the selected text from another app.") {
                Picker("Capture Shortcut", selection: $model.captureShortcut) {
                    Text("Shift, Shift").tag("Shift, Shift")
                    Text("Control-Option-C").tag("Control-Option-C")
                }.labelsHidden().controlSize(.small).frame(width: 150)
            }
            item("Accessibility", model.accessibilityEnabled ? "Enabled. Piper can read a selection." : "Not enabled. Piper cannot read a selection.") {
                Button("Open System Settings") { model.requestAccessibility() }.buttonStyle(PiperButtonStyle())
            }
            item("Capture Clipboard", "Use it when an app does not expose its selection.") {
                Button("Capture Now") { model.store.captureClipboard() }.buttonStyle(PiperButtonStyle())
            }
        }
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Applies to the Wiki page. Markdown files do not change.").font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary)
            ReadingPreferencesView().frame(maxWidth: 420)
        }.padding(.top, 8)
    }

    private var style: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Style", selection: $model.style) {
                ForEach(PiperStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 220).accessibilityLabel("Application Style")
            Text(model.style.summary).font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary)
            Text("Both styles keep the same layout and shortcuts.").font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary)
        }.padding(.top, 8)
    }

    private var data: some View {
        item("Notes", "Stored in Application Support/Piper. Core functions need no network connection.") {
            Button("Show in Finder") {
                NSWorkspace.shared.open(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Piper"))
            }.buttonStyle(PiperButtonStyle())
        }
    }

    private func item<Control: View>(_ title: String, _ detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(PiperTheme.ui(12.5))
                Text(detail).font(PiperTheme.ui(11.5)).foregroundStyle(PiperTheme.secondary).textSelection(.enabled)
            }
            Spacer()
            control()
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Rule() }
    }
}
