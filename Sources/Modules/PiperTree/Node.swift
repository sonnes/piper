import Foundation

/// One item in a tree that backs an outline view.
///
/// A node holds a represented object and the nodes below it. The parent
/// reference is weak, so a tree keeps its children alive from the root down.
public final class Node {

    // MARK: - Properties

    public weak var parent: Node?
    public var children = [Node]()
    public let representedObject: Any
    /// `true` when the node accepts children, even where it has none yet.
    public var canHaveChildren = false
    /// `true` when an outline view draws the node as a section header.
    public var isGroupItem = false

    public var isRoot: Bool { parent == nil }

    public var hasChildNodes: Bool { !children.isEmpty }

    /// The distance from the root. The root is at level 0.
    public var level: Int {
        guard let parent else { return 0 }
        return parent.level + 1
    }

    /// The position of the node under each of its ancestors, from the root down.
    public var indexPath: IndexPath {
        guard let parent else { return IndexPath(index: 0) }
        guard let index = parent.indexOfChild(self) else {
            preconditionFailure("The parent of a node must hold it as a child.")
        }
        return parent.indexPath.appending(index)
    }

    // MARK: - Lifecycle

    public init(representedObject: Any, parent: Node?) {
        self.representedObject = representedObject
        self.parent = parent
    }

    /// Makes a parentless node that accepts children.
    public static func root(representedObject: Any) -> Node {
        let node = Node(representedObject: representedObject, parent: nil)
        node.canHaveChildren = true
        return node
    }

    // MARK: - Children

    public func childAtIndex(_ index: Int) -> Node? {
        guard children.indices.contains(index) else { return nil }
        return children[index]
    }

    public func indexOfChild(_ node: Node) -> Int? {
        children.firstIndex { $0 === node }
    }

    /// Finds the first node below this one that passes the test.
    ///
    /// The walk goes depth first and includes every level below this node.
    public func descendantNode(where test: (Node) -> Bool) -> Node? {
        for child in children {
            if test(child) { return child }
            if let found = child.descendantNode(where: test) { return found }
        }
        return nil
    }
}

// MARK: - Equatable

extension Node: Equatable {

    public static func == (lhs: Node, rhs: Node) -> Bool {
        lhs === rhs
    }
}
