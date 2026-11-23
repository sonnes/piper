// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Piper",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Piper", targets: ["Piper"])],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2")
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),

        // Bottom modules. These add no dependency on another Piper module.
        .target(name: "PiperCore", dependencies: ["Yams"], path: "Sources/Modules/PiperCore"),
        .target(name: "CapturesDatabase", dependencies: ["CSQLite"], path: "Sources/Modules/CapturesDatabase"),

        // Middle modules.
        .target(name: "Captures", dependencies: ["PiperCore", "CapturesDatabase"], path: "Sources/Modules/Captures"),
        .target(name: "Vault", dependencies: ["PiperCore", "Yams"], path: "Sources/Modules/Vault"),
        .target(name: "Agents", dependencies: ["PiperCore", "CapturesDatabase"], path: "Sources/Modules/Agents"),
        .target(name: "History", dependencies: ["PiperCore", "CSQLite"], path: "Sources/Modules/History"),
        .target(name: "Feeds", dependencies: ["CSQLite"], path: "Sources/Modules/Feeds", exclude: ["RSParser/README.md"]),
        .target(name: "Stream", dependencies: ["Captures", "Feeds"], path: "Sources/Modules/Stream"),

        // Application target.
        .executableTarget(name: "Piper", dependencies: [
            "CSQLite", "Yams",
            "PiperCore", "CapturesDatabase", "Captures", "Vault", "Agents", "History", "Feeds", "Stream"
        ], resources: [.process("Resources")]),

        .testTarget(name: "PiperTests", dependencies: ["Piper"]),
        .testTarget(name: "CapturesTests", dependencies: ["Captures"], path: "Tests/CapturesTests"),
        .testTarget(name: "AgentsTests", dependencies: ["Agents"], path: "Tests/AgentsTests"),
        .testTarget(name: "HistoryTests", dependencies: ["History", "CSQLite"], path: "Tests/HistoryTests"),
        .testTarget(name: "FeedsTests", dependencies: ["Feeds", "CSQLite"], path: "Tests/FeedsTests",
                    resources: [.copy("Resources")]),
        .testTarget(name: "StreamTests", dependencies: ["Stream", "Captures", "Feeds", "CSQLite"], path: "Tests/StreamTests"),
        .testTarget(name: "VaultTests", dependencies: ["Vault"], path: "Tests/VaultTests"),
        .testTarget(name: "PiperCoreTests", dependencies: ["PiperCore"], path: "Tests/PiperCoreTests")
    ]
)
