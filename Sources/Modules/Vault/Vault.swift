import Foundation
import PiperCore

/// The result of one scan of the vault folder.
public struct VaultScan {

    /// Every regular file below the root, sorted by path.
    public let files: [VaultFile]
    /// Every folder below the root, sorted by path. A folder that holds no file
    /// is here, because the browser shows it.
    public let folders: [String]
    /// The files that Piper could not read, with the reason for each one.
    public let problems: [String]

    public init(files: [VaultFile], folders: [String] = [], problems: [String]) {
        self.files = files
        self.folders = folders
        self.problems = problems
    }
}

/// A folder of files that Piper browses.
///
/// The vault has no required layout, no required file names, and no required
/// metadata. Piper reads the folder and reports what is in it.
public struct Vault {

    // MARK: Properties

    /// The root folder, with symbolic links in the path resolved.
    public let root: URL

    /// The size limit for a file that Piper loads into memory during a scan.
    ///
    /// A larger file is listed with `isText` false and no text. The reader can
    /// still see its name, its size, and its date.
    public static let textSizeLimit = 4 * 1024 * 1024

    /// The folder names that a scan does not enter.
    public static let skippedFolders: Set<String> = ["node_modules", "venv", "__pycache__"]

    // MARK: Lifecycle

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    // MARK: Folder

    /// Creates the root folder.
    ///
    /// The folder must be absent or empty. Piper writes no file into it, because
    /// an empty folder is a valid vault.
    public func create() throws {
        let files = FileManager.default
        if files.fileExists(atPath: root.path) {
            let contents = try files.contentsOfDirectory(atPath: root.path).filter { $0 != ".DS_Store" }
            guard contents.isEmpty else {
                throw PiperError("Choose an empty folder for a new vault. Existing files remain unchanged.")
            }
        }
        try files.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Returns the URL for a path inside the vault.
    ///
    /// A path that starts with a slash is relative to the root. Any other path is
    /// relative to the folder of `document`, or to the root when `document` is nil.
    /// A path that leaves the root throws, and so does a path through a symbolic link.
    public func containedURL(_ path: String, relativeTo document: String? = nil) throws -> URL {
        let base = document.map { root.appendingPathComponent($0).deletingLastPathComponent() } ?? root
        let url = (path.hasPrefix("/")
            ? root.appendingPathComponent(String(path.dropFirst()))
            : base.appendingPathComponent(path)).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { throw PiperError("This path leaves the vault folder.") }
        var componentURL = root
        for component in url.path.dropFirst(root.path.count + 1).split(separator: "/") {
            componentURL.appendPathComponent(String(component))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: componentURL.path)) != nil {
                throw PiperError("Piper does not follow symbolic links inside the vault.")
            }
        }
        return url
    }

    // MARK: Files

    /// Lists every regular file below the root.
    ///
    /// The scan skips hidden files, symbolic links, and the folders in
    /// `skippedFolders`. A file that Piper cannot read goes into `problems`, and
    /// the scan continues. The scan lists the folders as well as the files,
    /// because a folder that holds no file is still a place to put one.
    public func scan() throws -> VaultScan {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw PiperError("The vault folder is unavailable. Choose a folder in Settings.")
        }
        var problems: [String] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                                      .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
            errorHandler: { url, error in
                problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
                return true
            }
        ) else { throw PiperError("Cannot read the vault folder.") }

        var files: [VaultFile] = []
        var folders: [String] = []
        for case let url as URL in enumerator {
            if Self.skippedFolders.contains(url.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            let values: URLResourceValues
            do { values = try url.resourceValues(forKeys: Set(keys)) }
            catch {
                problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            if values.isDirectory == true {
                folders.append(relativePath(of: url))
                continue
            }
            guard values.isRegularFile == true else { continue }
            let path = relativePath(of: url)
            do { files.append(try file(at: url, path: path, values: values)) }
            catch { problems.append("\(path): \(error.localizedDescription)") }
        }
        let sorted = files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
        let sortedFolders = folders.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return VaultScan(files: sorted, folders: sortedFolders, problems: problems)
    }

    /// Reads one file at a path inside the vault.
    public func read(_ path: String) throws -> VaultFile {
        let url = try containedURL(path)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let values = try url.resourceValues(forKeys: Set(keys))
        guard values.isRegularFile == true else { throw PiperError("\(path) is not a file.") }
        return try file(at: url, path: relativePath(of: url), values: values)
    }

    /// Writes text to a path inside the vault.
    ///
    /// The write is atomic. Piper creates the parent folders that are missing.
    public func write(_ text: String, to path: String) throws {
        let url = try containedURL(path)
        let folder = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        try Data(text.utf8).write(to: url, options: .atomic)
    }
}

// MARK: - Reading

private extension Vault {

    func relativePath(of url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        guard path.hasPrefix(root.path + "/") else { return url.lastPathComponent }
        return String(path.dropFirst(root.path.count + 1))
    }

    func file(at url: URL, path: String, values: URLResourceValues) throws -> VaultFile {
        let size = values.fileSize ?? 0
        let modifiedAt = values.contentModificationDate ?? Date.distantPast
        var text: String?
        if size <= Self.textSizeLimit {
            let data = try Data(contentsOf: url)
            if !data.contains(0) { text = String(data: data, encoding: .utf8) }
        }
        return VaultFile(relativePath: path, size: size, modifiedAt: modifiedAt, text: text)
    }
}
