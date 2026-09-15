import Foundation
import Observation
import Vault

/// Stores the modification timestamp last read for each file in each Wiki folder.
@MainActor @Observable
final class FileReadState {
    private let defaults: UserDefaults
    private static let key = "wikiReadTimestamps"
    private var timestamps: [String: [String: Double]]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        timestamps = defaults.dictionary(forKey: Self.key) as? [String: [String: Double]] ?? [:]
    }

    func isUnread(_ file: VaultFile, in root: URL) -> Bool {
        timestamps[root.standardizedFileURL.path]?[file.id] != file.modifiedAt.timeIntervalSince1970
    }

    func markRead(_ file: VaultFile, in root: URL) {
        guard isUnread(file, in: root) else { return }
        timestamps[root.standardizedFileURL.path, default: [:]][file.id] = file.modifiedAt.timeIntervalSince1970
        defaults.set(timestamps, forKey: Self.key)
    }
}
