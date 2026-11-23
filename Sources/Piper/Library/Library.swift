import AppKit
import Agents
import Observation
import Vault

/// The file editor of the active folder. The library asks it before the
/// folder changes, and tells it what each scan found.
@MainActor
protocol LibraryDelegate: AnyObject {
    /// Saves each edit. False keeps the active folder.
    func librarySettle(_ library: Library) -> Bool
    func libraryDidChangeFolder(_ library: Library)
    /// - Parameter previous: The files before the scan.
    func library(_ library: Library, didScan previous: [VaultFile])
}

/// The folders of the user, and the files of the active folder.
///
/// Piper scans one folder at a time. A `VaultWatcher` scans it again when its
/// files change.
@MainActor @Observable
final class Library {
    private(set) var wikiPaths: [String] {
        didSet {
            preferences.set(wikiPaths, forKey: AppDefaults.Key.wikiPaths)
            agents.refresh(paths: wikiPaths)
        }
    }
    var wikiPath: String {
        didSet {
            preferences.set(wikiPath, forKey: AppDefaults.Key.vaultPath)
            if let watcher, watcher.vault.root != vault.root { reload() }
        }
    }
    var files: [VaultFile] = []
    /// Every folder of the vault, including the ones that hold no file.
    var folders: [String] = []
    var problems: [String] = []
    /// Why the last scan failed, for example a folder that does not exist.
    private(set) var scanError: String?
    private(set) var loading = false
    @ObservationIgnored weak var delegate: LibraryDelegate?
    /// Called after the active folder changes, before its first scan.
    @ObservationIgnored var folderChanged: (() -> Void)?
    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var reloadPending = false
    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let agents: FolderAgents

    /// - Parameter wikiPath: The active folder. Nil reads it from the preferences.
    init(wikiPath: String?, preferences: UserDefaults, agents: FolderAgents) {
        self.preferences = preferences
        self.agents = agents
        let activePath = wikiPath ?? preferences.string(forKey: AppDefaults.Key.vaultPath) ?? Vault.defaultPath
        self.wikiPath = activePath
        var savedPaths = wikiPath == nil ? preferences.stringArray(forKey: AppDefaults.Key.wikiPaths) ?? [] : []
        if !savedPaths.contains(activePath) { savedPaths.append(activePath) }
        self.wikiPaths = savedPaths
        agents.refresh(paths: savedPaths)
    }

    var vault: Vault { Vault(path: wikiPath) }

    func reload() {
        agents.refresh(paths: wikiPaths)
        let repo = vault
        if watcher?.vault.root != repo.root {
            watcher?.stop()
            let watcher = VaultWatcher(vault: repo) { [weak self] in self?.reload() }
            self.watcher = watcher
            watcher.start()
        }
        guard !loading else { reloadPending = true; return }
        reloadPending = false
        loading = true
        Task {
            defer {
                loading = false
                if reloadPending { reload() }
            }
            let result = await Task.detached { Result { try repo.scan() } }.value
            guard repo.root == vault.root else {
                reloadPending = true
                return
            }
            switch result {
            case .success(let scan):
                problems = scan.problems
                scanError = nil
                let previous = files
                files = scan.files
                folders = scan.folders
                delegate?.library(self, didScan: previous)
            case .failure(let error):
                files = []
                folders = []
                scanError = error.localizedDescription
            }
        }
    }

    func chooseWiki() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders. Each folder gets a tab."
        guard panel.runModal() == .OK else { return }
        addWikiFolders(panel.urls.map(\.path))
    }

    /// Takes a folder off the folder list and its tab off the feed paper. The folder on disk does not change.
    ///
    /// The active folder moves to the next folder in the list first. The last
    /// folder stays, because the window needs one folder to show.
    func removeWikiFolder(_ path: String) {
        guard wikiPaths.count > 1, let index = wikiPaths.firstIndex(of: path) else { return }
        if path == wikiPath {
            let next = wikiPaths[index == 0 ? 1 : index - 1]
            changeWiki(to: next)
            guard wikiPath == next else { return }
        }
        wikiPaths.removeAll { $0 == path }
    }

    func addWikiFolders(_ paths: [String]) {
        guard let first = paths.first, delegate?.librarySettle(self) ?? true else { return }
        for path in paths { registerWikiFolder(path) }
        changeWiki(to: first)
    }

    func changeWiki(to path: String) {
        guard delegate?.librarySettle(self) ?? true else { return }
        wikiPath = registerWikiFolder(path)
        files = []
        folders = []
        delegate?.libraryDidChangeFolder(self)
        folderChanged?()
        reload()
    }

    /// Returns the listed path of the folder, and adds the folder when the list
    /// does not have it. Two paths to the same folder are one folder.
    @discardableResult private func registerWikiFolder(_ path: String) -> String {
        let root = Vault(path: path).root
        if let existing = wikiPaths.first(where: { Vault(path: $0).root == root }) { return existing }
        wikiPaths.append(path)
        return path
    }
}
