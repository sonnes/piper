import Foundation

/// The source of the children of each node.
public protocol TreeControllerDelegate: AnyObject {

    func treeController(treeController: TreeController, childNodesFor node: Node) -> [Node]?
}

public typealias NodeVisitBlock = (Node) -> Void

/// The tree behind an outline view.
///
/// The controller owns the root node. It asks the delegate for the children of
/// each node that accepts children, and it repeats that walk on every rebuild.
public final class TreeController {

    // MARK: - Properties

    public let rootNode: Node
    private weak var delegate: TreeControllerDelegate?

    // MARK: - Lifecycle

    public init(delegate: TreeControllerDelegate, rootNode: Node) {
        self.delegate = delegate
        self.rootNode = rootNode
        rebuild()
    }

    // MARK: - Building

    /// Asks the delegate for the children of every node again.
    ///
    /// The result is `true` where the tree changed.
    @discardableResult
    public func rebuild() -> Bool {
        rebuildChildNodes(node: rootNode)
    }

    // MARK: - Lookup

    public func visitNodes(_ visitBlock: NodeVisitBlock) {
        visitNode(rootNode, visitBlock)
    }

    /// Finds the first node in the array that holds the given object.
    ///
    /// Where `recurse` is `true`, the search also reads the children of each node.
    public func nodeInArrayRepresentingObject<Object: Equatable>(nodes: [Node], representedObject: Object, recurse: Bool = false) -> Node? {
        for node in nodes {
            if let object = node.representedObject as? Object, object == representedObject { return node }
            if recurse, let found = nodeInArrayRepresentingObject(nodes: node.children, representedObject: representedObject, recurse: true) {
                return found
            }
        }
        return nil
    }

    /// Finds the node anywhere in the tree that holds the given object.
    public func nodeInTreeRepresentingObject<Object: Equatable>(_ representedObject: Object) -> Node? {
        nodeInArrayRepresentingObject(nodes: [rootNode], representedObject: representedObject, recurse: true)
    }
}

// MARK: - Private

private extension TreeController {

    func visitNode(_ node: Node, _ visitBlock: NodeVisitBlock) {
        visitBlock(node)
        for child in node.children {
            visitNode(child, visitBlock)
        }
    }

    func rebuildChildNodes(node: Node) -> Bool {
        guard node.canHaveChildren else { return false }
        let children = delegate?.treeController(treeController: self, childNodesFor: node) ?? [Node]()
        var didChange = children != node.children
        if didChange { node.children = children }
        for child in children where rebuildChildNodes(node: child) {
            didChange = true
        }
        return didChange
    }
}
