import Foundation
import Vault

/// One visible row of the folder tree of a folder tab.
struct FolderTreeRow: Equatable, Identifiable {
    /// The absolute path. The cursor and the open folders name a row by it.
    let id: String
    /// The path from the root of the active folder.
    let path: String
    let name: String
    let isFolder: Bool
    /// The level of the row. A row at the top of the tree is at level 0.
    let depth: Int
    /// The row of the folder that holds this row, or nil at the top of the tree.
    let parent: String?
    /// True for an open folder.
    let expanded: Bool
    /// The number of files under a folder. A file has 1.
    let count: Int
}

enum FolderTreeKey: Equatable {
    case up, down, left, right, enter
}

enum FolderTreeAction: Equatable {
    /// Move the cursor to the row.
    case select(String)
    case expand(String)
    case collapse(String)
    /// Open the file as a file paper.
    case openFile(String)
    case none
}

/// The rows of the folder tree and the keys that move through it.
enum FolderTree {

    /// The rows that show, in the order of the tree. The rows of a folder
    /// show only while the folder is in `expanded`.
    ///
    /// - Parameters:
    ///   - paths: The files of the active folder, as paths from its root.
    ///   - folders: The folders of the active folder, as paths from its root.
    ///   - root: The active folder, by its absolute path.
    ///   - expanded: The open folders, by their absolute paths.
    static func rows(paths: [String], folders: [String], root: String, expanded: Set<String>) -> [FolderTreeRow] {
        let base = Vault(path: root).root
        var rows: [FolderTreeRow] = []

        func visit(_ nodes: [PathNode], depth: Int, parent: String?) {
            for node in nodes {
                let id = base.appendingPathComponent(node.path).path
                let open = node.isFolder && expanded.contains(id)
                rows.append(FolderTreeRow(id: id, path: node.path, name: node.name, isFolder: node.isFolder, depth: depth,
                                          parent: parent, expanded: open, count: node.count))
                if open { visit(node.children, depth: depth + 1, parent: id) }
            }
        }

        visit(PathTreeBuilder.nodes(paths: paths, folders: folders, folder: ""), depth: 0, parent: nil)
        return rows
    }

    /// What a key does on the row under the cursor.
    ///
    /// Up Arrow and Down Arrow move through the rows that show. Right Arrow
    /// opens a closed folder, and moves into an open folder. Left Arrow
    /// closes an open folder, and moves from another row to its folder.
    /// Return opens a file, and opens or closes a folder.
    static func action(_ key: FolderTreeKey, cursor: String?, rows: [FolderTreeRow]) -> FolderTreeAction {
        guard let first = rows.first else { return .none }
        guard let cursor, let index = rows.firstIndex(where: { $0.id == cursor }) else { return .select(first.id) }
        let row = rows[index]
        switch key {
        case .up:
            return .select(rows[max(0, index - 1)].id)
        case .down:
            return .select(rows[min(rows.count - 1, index + 1)].id)
        case .right:
            guard row.isFolder else { return .none }
            if !row.expanded { return .expand(row.id) }
            if index + 1 < rows.count, rows[index + 1].parent == row.id { return .select(rows[index + 1].id) }
            return .none
        case .left:
            if row.isFolder, row.expanded { return .collapse(row.id) }
            return row.parent.map(FolderTreeAction.select) ?? .none
        case .enter:
            if row.isFolder { return row.expanded ? .collapse(row.id) : .expand(row.id) }
            return .openFile(row.id)
        }
    }
}

/// A folder or a file of the tree, with the nodes below it.
private struct PathNode {
    /// The path from the root of the tree.
    let path: String
    let name: String
    let isFolder: Bool
    /// The number of files under a folder. A file has 1.
    let count: Int
    let children: [PathNode]
}

/// Builds the tree of folders and files from paths such as `engineering/rfcs/a.md`.
///
/// Under each folder the child folders come first, then the files. Both
/// groups are in the order of `localizedStandardCompare`. A path in `folders`
/// gets a node, so that a folder with no file is in the tree with a count of 0.
private enum PathTreeBuilder {

    static func nodes(paths: [String], folders: [String], folder: String) -> [PathNode] {
        let prefix = folder.isEmpty ? "" : folder + "/"
        let descendants = paths.filter { $0.hasPrefix(prefix) }
        let folderDescendants = folders.filter { $0.hasPrefix(prefix) }
        var folderNames = Set(descendants.compactMap { path -> String? in
            let parts = path.dropFirst(prefix.count).split(separator: "/")
            return parts.count > 1 ? String(parts[0]) : nil
        })
        for path in folderDescendants {
            guard let first = path.dropFirst(prefix.count).split(separator: "/").first else { continue }
            folderNames.insert(String(first))
        }
        let branches = folderNames.sorted(by: precedes).map { name -> PathNode in
            let path = prefix + name
            let count = descendants.filter { $0.hasPrefix(path + "/") }.count
            return PathNode(path: path, name: name, isFolder: true, count: count,
                            children: nodes(paths: descendants, folders: folderDescendants, folder: path))
        }
        let leaves = descendants.filter { ($0 as NSString).deletingLastPathComponent == folder }
            .sorted { precedes(($0 as NSString).lastPathComponent, ($1 as NSString).lastPathComponent) }
            .map { PathNode(path: $0, name: ($0 as NSString).lastPathComponent, isFolder: false, count: 1, children: []) }
        return branches + leaves
    }

    private static func precedes(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
