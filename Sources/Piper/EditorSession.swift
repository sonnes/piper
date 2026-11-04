import Foundation
import Observation
import PiperCore
import Vault

/// How the text on disk relates to the text in the editor.
///
/// The editor saves by itself, so Piper compares three texts before it writes:
/// the text that Piper last read or wrote (the baseline), the text in the
/// editor, and the text on disk. Hubble.md uses the same rules.
enum DiskChange: Equatable {
    /// The disk holds the baseline. Piper can write the editor text.
    case unchanged
    /// The disk already holds the editor text.
    case match
    /// The disk changed, and the editor has no edits. Piper loads the disk text.
    case clean
    /// The disk changed, and the editor has edits. Piper does not write.
    case conflict

    /// A nil disk text means that the file is gone.
    static func classify(baseline: String, editor: String, disk: String?) -> DiskChange {
        guard let disk else { return editor == baseline ? .clean : .conflict }
        if disk == baseline { return .unchanged }
        if disk == editor { return .match }
        if editor == baseline { return .clean }
        return .conflict
    }
}

/// The open Markdown file in the editor, with the text that is not on disk yet.
@MainActor @Observable
final class EditorSession {
    enum Status: Equatable {
        case opened
        case saved
        /// The file changed on disk while the editor had edits. Saves stop until the reader chooses.
        case conflict
        case failed(String)
    }

    let path: String
    /// The last state of the file that Piper read. A deleted file keeps it while it has edits.
    var document: VaultFile
    /// The text that Piper last read from disk or wrote to disk.
    private(set) var baseline: String
    /// The text in the editor, with the frontmatter.
    var text: String
    private(set) var status = Status.opened
    /// The syntax that the rich editor would drop. The rich editor is read-only while it is not empty.
    var lossy: [String] = []
    /// Increases each time Piper puts the disk text into the editor.
    private(set) var revision = 0

    var hasChanges: Bool { text != baseline }
    var isBlocked: Bool {
        if case .opened = status { return false }
        if case .saved = status { return false }
        return true
    }

    init(document: VaultFile) {
        path = document.id
        self.document = document
        baseline = document.raw
        text = document.raw
    }

    /// Writes the editor text if the file on disk did not change. Returns false
    /// when the text is not on disk after the call.
    @discardableResult
    func save(in vault: Vault) -> Bool {
        if status == .conflict { return false }
        let disk = Self.read(path, in: vault)
        switch DiskChange.classify(baseline: baseline, editor: text, disk: disk) {
        case .unchanged:
            guard hasChanges else { return true }
            return write(in: vault)
        case .match:
            baseline = text
            status = .saved
            return true
        case .clean:
            if let disk { load(disk) }
            return true
        case .conflict:
            status = .conflict
            return false
        }
    }

    /// Reads the file after a change on disk. A file without edits loads the
    /// new text. A file with edits gets a conflict.
    func diskChanged(in vault: Vault) {
        let disk = Self.read(path, in: vault)
        switch DiskChange.classify(baseline: baseline, editor: text, disk: disk) {
        case .unchanged: break
        case .match:
            baseline = text
            if status == .conflict { status = .saved }
        case .clean:
            if let disk { load(disk) }
        case .conflict:
            status = .conflict
        }
    }

    /// Writes the editor text over the change on disk.
    @discardableResult
    func keepMine(in vault: Vault) -> Bool {
        write(in: vault)
    }

    /// Puts the disk text into the editor and drops the edits.
    func reloadFromDisk(in vault: Vault) {
        guard let disk = Self.read(path, in: vault) else { return }
        load(disk)
    }

    private func load(_ disk: String) {
        baseline = disk
        text = disk
        revision += 1
        status = .opened
    }

    private func write(in vault: Vault) -> Bool {
        do {
            try vault.write(text, to: path)
            baseline = text
            status = .saved
            return true
        } catch {
            status = .failed(error.localizedDescription)
            return false
        }
    }

    static func read(_ path: String, in vault: Vault) -> String? {
        guard let url = try? vault.containedURL(path), let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
