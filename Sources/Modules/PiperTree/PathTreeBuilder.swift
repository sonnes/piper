import Foundation

/// A folder or a file in a path tree.
public struct PathItem: Equatable {

    /// The path relative to the root of the tree. The root itself holds an empty path.
    public let path: String
    /// The last component of the path.
    public let name: String
    public let isFolder: Bool
    /// The number of files under a folder. A file holds the value 1.
    public let count: Int

    public init(path: String, name: String, isFolder: Bool, count: Int) {
        self.path = path
        self.name = name
        self.isFolder = isFolder
        self.count = count
    }
}

/// The builder of a tree of folders and files from a list of relative paths.
public enum PathTreeBuilder {

    /// Builds a tree from relative file paths such as `engineering/rfcs/a.md`.
    ///
    /// Under each folder the child folders come first, then the files. Both
    /// groups are in the order of `localizedStandardCompare`. The root node
    /// holds an empty path and the count of every file.
    ///
    /// A path in `folders` gets a node of its own, so that a folder which holds
    /// no file is still in the tree. Its count is 0.
    public static func tree(paths: [String], folders: [String] = [], includingFiles: Bool = true) -> Node {
        let root = Node.root(representedObject: PathItem(path: "", name: "", isFolder: true, count: paths.count))
        root.children = childNodes(paths: paths, folders: folders, parent: root, folder: "", includingFiles: includingFiles)
        return root
    }
}

// MARK: - Private

private extension PathTreeBuilder {

    static func childNodes(paths: [String], folders: [String], parent: Node, folder: String, includingFiles: Bool) -> [Node] {
        let prefix = folder.isEmpty ? "" : folder + "/"
        let descendants = paths.filter { $0.hasPrefix(prefix) }
        let folderDescendants = folders.filter { $0.hasPrefix(prefix) }
        // A file names a folder only when it is below one. A folder path names
        // itself, so its first component is always a folder at this level.
        var folderNames = Set(descendants.compactMap { path -> String? in
            let parts = path.dropFirst(prefix.count).split(separator: "/")
            return parts.count > 1 ? String(parts[0]) : nil
        })
        for path in folderDescendants {
            guard let first = path.dropFirst(prefix.count).split(separator: "/").first else { continue }
            folderNames.insert(String(first))
        }
        let branches = folderNames.sorted(by: precedes).map { name -> Node in
            let path = prefix + name
            let count = descendants.filter { $0.hasPrefix(path + "/") }.count
            let node = Node(representedObject: PathItem(path: path, name: name, isFolder: true, count: count), parent: parent)
            node.canHaveChildren = true
            node.children = childNodes(paths: descendants, folders: folderDescendants, parent: node, folder: path, includingFiles: includingFiles)
            return node
        }
        guard includingFiles else { return branches }
        let leaves = descendants.filter { ($0 as NSString).deletingLastPathComponent == folder }
            .sorted { precedes(($0 as NSString).lastPathComponent, ($1 as NSString).lastPathComponent) }
            .map { path -> Node in
                let name = (path as NSString).lastPathComponent
                return Node(representedObject: PathItem(path: path, name: name, isFolder: false, count: 1), parent: parent)
            }
        return branches + leaves
    }

    static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
