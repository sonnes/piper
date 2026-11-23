import Foundation

/// The folder that holds the databases and caches of Piper:
/// `~/Library/Application Support/Piper`.
public enum DataFolder {
    public static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Piper")
    }
}
