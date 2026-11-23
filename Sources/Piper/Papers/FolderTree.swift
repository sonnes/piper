import Foundation
import PiperTree

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
    ///   - root: The active folder, by its absolute path.
    ///   - expanded: The open folders, by their absolute paths.
    static func rows(paths: [String], folders: [String], root: String, expanded: Set<String>) -> [FolderTreeRow] {
        let base = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
        var rows: [FolderTreeRow] = []

        func visit(_ node: Node, depth: Int, parent: String?) {
            for child in node.children {
                guard let item = child.representedObject as? PathItem else { continue }
                let id = base.appendingPathComponent(item.path).path
                let open = item.isFolder && expanded.contains(id)
                rows.append(FolderTreeRow(id: id, path: item.path, name: item.name, isFolder: item.isFolder, depth: depth,
                                          parent: parent, expanded: open, count: item.count))
                if open { visit(child, depth: depth + 1, parent: id) }
            }
        }

        visit(PathTreeBuilder.tree(paths: paths, folders: folders), depth: 0, parent: nil)
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
