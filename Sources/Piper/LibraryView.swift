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

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if saved {
                Label("Draft Saved", systemImage: "checkmark.circle.fill").font(.title2)
                Text(title).font(.headline)
                Text(model.selectedDocument ?? "").font(.caption).textSelection(.enabled)
                Text("Your captures remain in Piper. The Wiki draft is unverified.").foregroundStyle(PiperTheme.secondary)
                HStack {
                    Button("Done") { dismiss() }
                    Spacer()
                    Button("Read in Wiki") { dismiss(); model.openLibrary?() }.buttonStyle(.borderedProminent).foregroundStyle(PiperTheme.page)
                }
            } else {
            Text("Send to Wiki").font(.title2.bold())
            Text("\(model.exportNotes.count) captures · One draft · Originals stay in Piper").font(.caption).foregroundStyle(PiperTheme.secondary)
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $description, axis: .vertical).lineLimit(2...4)
                Picker("Destination", selection: $destination) {
                    ForEach(WikiRepository.destinations, id: \.self) { Text($0.capitalized).tag($0) }
                }
                TextField("Source URL (optional)", text: $sourceURL)
            }.textFieldStyle(.roundedBorder)
            Text("\(destination)/\(WikiRepository.slug(title)).md").font(.system(size: 10, design: .monospaced)).foregroundStyle(PiperTheme.secondary)
            ScrollView { Text(model.exportNotes.map(\.text).joined(separator: "\n\n")).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12) }
                .frame(height: 150).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            if let error { Text(error).font(.caption).foregroundStyle(PiperTheme.danger).textSelection(.enabled) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(model.exporting)
                Spacer()
                if model.exporting { ProgressView().controlSize(.small) }
                Button("Save Draft") {
                    Task {
                        error = await model.export(title: title, description: description, destination: destination, sourceURL: sourceURL)
                        saved = error == nil
                    }
                }.buttonStyle(.borderedProminent).foregroundStyle(PiperTheme.page)
                    .disabled(model.exporting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            }
        }.padding(22).frame(width: 490)
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
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    var body: some View {
        Form {
            Section("Wiki") {
                Text((model.wikiPath as NSString).abbreviatingWithTildeInPath).textSelection(.enabled)
                Button("Choose Wiki Folder") { model.chooseWiki() }
                Text("Exports create unverified drafts. Existing concepts remain unchanged.").font(.caption).foregroundStyle(PiperTheme.secondary)
            }
            Section("Capture") {
                Picker("Capture Shortcut", selection: $model.captureShortcut) {
                    Text("Shift, Shift").tag("Shift, Shift")
                    Text("Control-Option-C").tag("Control-Option-C")
                }
                HStack {
                    Text("Accessibility")
                    Spacer()
                    Text(model.accessibilityEnabled ? "Enabled" : "Not Enabled").foregroundStyle(PiperTheme.secondary)
                }
                Button("Open Accessibility Settings") {
                    model.requestAccessibility()
                }
                Button("Capture Clipboard") { model.store.captureClipboard() }
                Text("Use Capture Clipboard when an application does not expose its selected text.").font(.caption).foregroundStyle(PiperTheme.secondary)
            }
            Section("Local Data") {
                Text("Notes stay in Application Support/Piper. Core functions need no network connection.").font(.caption)
                Button("Show Note Storage") {
                    NSWorkspace.shared.open(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Piper"))
                }
            }
        }.formStyle(.grouped).onReceive(timer) { _ in model.accessibilityEnabled = AXIsProcessTrusted() }
    }
}
