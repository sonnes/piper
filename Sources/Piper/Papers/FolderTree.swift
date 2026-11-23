import Foundation
import PiperTree

/// One visible row of the folder tree of the Folders tab and of a pinned folder tab.
struct FolderTreeRow: Equatable, Identifiable {
    /// The absolute path. The cursor, the open folders, and the pins name a row by it.
    let id: String
    /// The path from the root of the active folder. A root has the empty path.
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
    /// True for a folder of the folder list that is not the active folder.
    /// Its files show after it becomes the active folder.
    let isOtherRoot: Bool
}

/// A key on the folder tree.
enum FolderTreeKey: Equatable {
    case up, down, left, right, enter
}

/// What a key on the folder tree does.
enum FolderTreeAction: Equatable {
    /// Move the cursor to the row.
    case select(String)
    /// Open the folder.
    case expand(String)
    /// Close the folder.
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
    ///   - roots: The folders of the folder list, by their absolute paths.
    ///   - activeRoot: The active folder, by its absolute path.
    ///   - top: The folder whose contents are the top of the tree, by its
    ///     absolute path. Nil shows the whole tree: each root when the list
    ///     has more than one, or the contents of the active folder.
    ///   - expanded: The open folders, by their absolute paths.
    static func rows(paths: [String], folders: [String], roots: [String], activeRoot: String,
                     top: String?, expanded: Set<String>) -> [FolderTreeRow] {
        let base = URL(fileURLWithPath: activeRoot)
        let tree = PathTreeBuilder.tree(paths: paths, folders: folders)
        var rows: [FolderTreeRow] = []

        func visit(_ node: Node, depth: Int, parent: String?) {
            for child in node.children {
                guard let item = child.representedObject as? PathItem else { continue }
                let id = base.appendingPathComponent(item.path).path
                let open = item.isFolder && expanded.contains(id)
                rows.append(FolderTreeRow(id: id, path: item.path, name: item.name, isFolder: item.isFolder, depth: depth,
                                          parent: parent, expanded: open, count: item.count, isOtherRoot: false))
                if open { visit(child, depth: depth + 1, parent: id) }
            }
        }

        if let top {
            guard let folder = PaperDeskState.relativePath(of: top, in: activeRoot),
                  let node = find(folder, in: tree) else { return [] }
            visit(node, depth: 0, parent: nil)
        } else if roots.count > 1 {
            for root in roots {
                let active = root == activeRoot
                let open = active && expanded.contains(root)
                rows.append(FolderTreeRow(id: root, path: "", name: URL(fileURLWithPath: root).lastPathComponent,
                                          isFolder: true, depth: 0, parent: nil, expanded: open,
                                          count: active ? paths.count : 0, isOtherRoot: !active))
                if open { visit(tree, depth: 1, parent: root) }
            }
        } else {
            visit(tree, depth: 0, parent: nil)
        }
        return rows
    }

    /// The number of folders at the top of the active folder.
    static func topFolderCount(paths: [String], folders: [String]) -> Int {
        let fromFiles = paths.compactMap { path -> Substring? in
            let parts = path.split(separator: "/", maxSplits: 1)
            return parts.count > 1 ? parts[0] : nil
        }
        return Set(fromFiles + folders.compactMap { $0.split(separator: "/").first }).count
    }

    /// The number of files in a folder and in the folders under it.
    ///
    /// - Parameter folder: The path of the folder from the root. The empty path is the root.
    static func fileCount(paths: [String], in folder: String) -> Int {
        guard !folder.isEmpty else { return paths.count }
        let prefix = folder + "/"
        return paths.filter { $0.hasPrefix(prefix) }.count
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

    // MARK: - Private

    /// The node of a folder, by its path from the root.
    private static func find(_ path: String, in tree: Node) -> Node? {
        guard !path.isEmpty else { return tree }
        var node = tree
        var walked = ""
        for part in path.split(separator: "/") {
            walked = walked.isEmpty ? String(part) : walked + "/" + part
            guard let next = node.children.first(where: { ($0.representedObject as? PathItem)?.path == walked }) else {
                return nil
            }
            node = next
        }
        return node
    }
}
