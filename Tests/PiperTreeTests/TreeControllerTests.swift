import XCTest
@testable import PiperTree

final class TreeControllerTests: XCTestCase {

    func testControllerBuildsRebuildsAndFindsNodes() throws {
        let delegate = PathTreeDelegate(paths: ["Research/Journal.md", "Start Here.md"])
        let controller = TreeController(delegate: delegate, rootNode: Node.root(representedObject: PathItem(path: "", name: "", isFolder: true, count: 0)))
        XCTAssertEqual(try paths(of: controller.rootNode.children), ["Research", "Start Here.md"])

        var visited = [String]()
        controller.visitNodes { node in
            if let item = node.representedObject as? PathItem { visited.append(item.path) }
        }
        XCTAssertEqual(visited, ["", "Research", "Research/Journal.md", "Start Here.md"])

        let journal = PathItem(path: "Research/Journal.md", name: "Journal.md", isFolder: false, count: 1)
        let found = try XCTUnwrap(controller.nodeInTreeRepresentingObject(journal))
        XCTAssertEqual(found.level, 2)
        XCTAssertNil(controller.nodeInArrayRepresentingObject(nodes: controller.rootNode.children, representedObject: journal))

        delegate.paths = ["Topics/Reading.md"]
        XCTAssertTrue(controller.rebuild())
        XCTAssertEqual(try paths(of: controller.rootNode.children), ["Topics"])
        XCTAssertNil(controller.nodeInTreeRepresentingObject(journal))
    }

    // MARK: - Helpers

    private func paths(of nodes: [Node]) throws -> [String] {
        try nodes.map { try XCTUnwrap($0.representedObject as? PathItem).path }
    }
}

private final class PathTreeDelegate: TreeControllerDelegate {

    var paths: [String]

    init(paths: [String]) {
        self.paths = paths
    }

    func treeController(treeController: TreeController, childNodesFor node: Node) -> [Node]? {
        guard node.isRoot else { return node.children }
        let children = PathTreeBuilder.tree(paths: paths).children
        for child in children {
            child.parent = node
        }
        return children
    }
}
