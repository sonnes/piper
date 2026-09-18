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

        // Bottom modules. These add no dependency on another Piper module.
        .target(name: "PiperCore", dependencies: ["Yams"], path: "Sources/Modules/PiperCore"),
        .target(name: "PiperTree", path: "Sources/Modules/PiperTree"),
        .target(name: "CapturesDatabase", dependencies: ["CSQLite"], path: "Sources/Modules/CapturesDatabase"),

        // Middle modules.
        .target(name: "Captures", dependencies: ["PiperCore", "CapturesDatabase"], path: "Sources/Modules/Captures"),
        .target(name: "Vault", dependencies: ["PiperCore", "Yams"], path: "Sources/Modules/Vault"),
        .target(name: "Agents", dependencies: ["PiperCore", "CapturesDatabase"], path: "Sources/Modules/Agents"),

        // Application target.
        .executableTarget(name: "Piper", dependencies: [
            "CSQLite", "Yams",
            "PiperCore", "PiperTree", "CapturesDatabase", "Captures", "Vault", "Agents",
            .product(name: "MarkdownEngine", package: "swift-markdown-engine")
        ], resources: [.process("Resources")]),

        .testTarget(name: "PiperTests", dependencies: ["Piper"]),
        .testTarget(name: "PiperTreeTests", dependencies: ["PiperTree"], path: "Tests/PiperTreeTests"),
        .testTarget(name: "CapturesTests", dependencies: ["Captures"], path: "Tests/CapturesTests"),
        .testTarget(name: "AgentsTests", dependencies: ["Agents"], path: "Tests/AgentsTests"),
        .testTarget(name: "VaultTests", dependencies: ["Vault"], path: "Tests/VaultTests"),
        .testTarget(name: "PiperCoreTests", dependencies: ["PiperCore"], path: "Tests/PiperCoreTests")
    ]
)
