import Foundation
import PiperTree

/// One visible row of the folder tree on the Folders index.
struct FolderIndexRow: Equatable, Identifiable {
    /// The path from the root of the active folder.
    let path: String
    let name: String
    let isFolder: Bool
    /// The level under the root. A child of the root is at level 1.
    let depth: Int
    /// True for a folder that holds at least one row.
    let hasChildren: Bool
    let expanded: Bool

    var id: String { path }
}

/// The rows of the folder tree that show on the Folders index.
enum FolderIndex {

    /// The rows under the root, in the order of the tree. The rows of a
    /// folder show only while the folder is in `expanded`.
    static func rows(paths: [String], folders: [String], expanded: Set<String>) -> [FolderIndexRow] {
        var rows: [FolderIndexRow] = []
        func visit(_ node: Node, depth: Int) {
            for child in node.children {
                guard let item = child.representedObject as? PathItem else { continue }
                let open = item.isFolder && expanded.contains(item.path)
                rows.append(FolderIndexRow(path: item.path, name: item.name, isFolder: item.isFolder, depth: depth,
                                           hasChildren: child.hasChildNodes, expanded: open))
                if open { visit(child, depth: depth + 1) }
            }
        }
        visit(PathTreeBuilder.tree(paths: paths, folders: folders), depth: 1)
        return rows
    }
}
