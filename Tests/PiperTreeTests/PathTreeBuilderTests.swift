import XCTest
@testable import PiperTree

final class PathTreeBuilderTests: XCTestCase {

    func testTreePreservesNestedFoldersAndCountsLeaves() throws {
        let root = PathTreeBuilder.tree(paths: ["Start Here.md", "Research/Interviews/Maya.md", "Research/Journal.md", "Topics/Reading.md"])
        XCTAssertEqual(try paths(of: root.children), ["Research", "Topics", "Start Here.md"])
        XCTAssertEqual(try item(root).count, 4)
        let research = try XCTUnwrap(root.childAtIndex(0))
        XCTAssertEqual(try item(research).count, 2)
        XCTAssertEqual(try paths(of: research.children), ["Research/Interviews", "Research/Journal.md"])
        let interviews = try XCTUnwrap(research.childAtIndex(0))
        XCTAssertEqual(try item(interviews).count, 1)
        let maya = try XCTUnwrap(interviews.childAtIndex(0))
        XCTAssertEqual(try item(maya).path, "Research/Interviews/Maya.md")
        XCTAssertEqual(maya.level, 3)
        XCTAssertEqual(maya.indexPath, IndexPath(indexes: [0, 0, 0, 0]))
    }

    /// A node holds its parent weakly. A caller that keeps only the children
    /// releases the root, and every top-level `indexPath` then reads as the
    /// same value, which makes the nodes indistinguishable.
    func testIndexPathsAreDistinctWhileTheRootLivesAndCollapseWhenItDoes() throws {
        var root: Node? = PathTreeBuilder.tree(paths: ["alpha/a.md", "beta/b.md", "gamma/c.md"])
        let children = try XCTUnwrap(root).children
        XCTAssertEqual(Set(children.map(\.indexPath)).count, 3)
        root = nil
        XCTAssertNil(children[0].parent)
        XCTAssertEqual(Set(children.map(\.indexPath)).count, 1)
    }

    func testFoldersSortBeforeFilesAndBothSortInOrder() throws {
        let root = PathTreeBuilder.tree(paths: ["page10.md", "page2.md", "Zeta/a.md", "alpha/b.md"])
        XCTAssertEqual(try paths(of: root.children), ["alpha", "Zeta", "page2.md", "page10.md"])
        XCTAssertTrue(try item(XCTUnwrap(root.childAtIndex(0))).isFolder)
        XCTAssertFalse(try item(XCTUnwrap(root.childAtIndex(2))).isFolder)
    }

    func testFolderWithoutFilesGetsANodeWithACountOfZero() throws {
        let root = PathTreeBuilder.tree(paths: ["notes/a.md"],
                                        folders: ["notes", "decisions", "references", "references/skills"])
        XCTAssertEqual(try paths(of: root.children), ["decisions", "notes", "references"])
        let decisions = try XCTUnwrap(root.childAtIndex(0))
        XCTAssertEqual(try item(decisions), PathItem(path: "decisions", name: "decisions", isFolder: true, count: 0))
        XCTAssertTrue(decisions.children.isEmpty)
        let references = try XCTUnwrap(root.childAtIndex(2))
        XCTAssertEqual(try paths(of: references.children), ["references/skills"])
    }

    func testFileAtRootHasNoFolderParent() throws {
        let root = PathTreeBuilder.tree(paths: ["todo.md", "engineering/a.md"])
        let todo = try XCTUnwrap(root.descendantNode { (try? item($0).path) == "todo.md" })
        XCTAssertTrue(try XCTUnwrap(todo.parent).isRoot)
        XCTAssertEqual(todo.level, 1)
        XCTAssertEqual(try item(todo), PathItem(path: "todo.md", name: "todo.md", isFolder: false, count: 1))
        XCTAssertFalse(todo.hasChildNodes)
        XCTAssertEqual(root.indexOfChild(todo), 1)
    }

    func testEmptyPathListYieldsEmptyTree() throws {
        let root = PathTreeBuilder.tree(paths: [])
        XCTAssertTrue(root.isRoot)
        XCTAssertFalse(root.hasChildNodes)
        XCTAssertNil(root.childAtIndex(0))
        XCTAssertNil(root.descendantNode { _ in true })
        XCTAssertEqual(try item(root).count, 0)
    }

    func testDescendantNodeFindsDeepNode() throws {
        let root = PathTreeBuilder.tree(paths: ["engineering/rfcs/2026/a.md", "engineering/b.md", "todo.md"])
        let deep = try XCTUnwrap(root.descendantNode { (try? item($0).name) == "a.md" })
        XCTAssertEqual(try item(deep).path, "engineering/rfcs/2026/a.md")
        XCTAssertEqual(deep.level, 4)
        XCTAssertNil(root.descendantNode { (try? item($0).name) == "missing.md" })
    }

    func testRepeatedFolderNameAtTwoDepthsStaysSeparate() throws {
        let root = PathTreeBuilder.tree(paths: ["docs/docs/deep.md", "docs/top.md"])
        XCTAssertEqual(try paths(of: root.children), ["docs"])
        let outer = try XCTUnwrap(root.childAtIndex(0))
        XCTAssertEqual(try item(outer).count, 2)
        XCTAssertEqual(try paths(of: outer.children), ["docs/docs", "docs/top.md"])
        let inner = try XCTUnwrap(outer.childAtIndex(0))
        XCTAssertEqual(try item(inner).count, 1)
        XCTAssertEqual(try paths(of: inner.children), ["docs/docs/deep.md"])
    }

    // MARK: - Helpers

    private func item(_ node: Node) throws -> PathItem {
        try XCTUnwrap(node.representedObject as? PathItem)
    }

    private func paths(of nodes: [Node]) throws -> [String] {
        try nodes.map { try item($0).path }
    }
}
