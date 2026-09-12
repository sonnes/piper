// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Piper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Piper", targets: ["Piper"])],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
        .package(url: "https://github.com/nodes-app/swift-markdown-engine.git", exact: "0.12.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .executableTarget(name: "Piper", dependencies: [
            "CSQLite", "Yams",
            .product(name: "MarkdownEngine", package: "swift-markdown-engine")
        ], resources: [.process("Resources")]),
        .testTarget(name: "PiperTests", dependencies: ["Piper"])
    ]
)
