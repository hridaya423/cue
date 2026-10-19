// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v15)],
    dependencies: [
        // On-device PII redaction (11.6 MB Core ML model, downloads on demand).
        // Pinned to 3.1.x: v3.2.0 is fresh — let it bake.
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git",
                 .upToNextMinor(from: "3.1.0")),
    ],
    targets: [
        .target(
            name: "CueKit",
            dependencies: [.product(name: "Redact", package: "desert-ant-core")],
            path: "Sources/CueKit",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "Cue",
            dependencies: ["CueKit"],
            path: "Sources/Cue"
        ),
        .executableTarget(
            name: "CueEval",
            dependencies: ["CueKit"],
            path: "Sources/CueEval"
        ),
        .executableTarget(
            name: "CueDay",
            dependencies: ["CueKit"],
            path: "Sources/CueDay"
        ),
        .executableTarget(
            name: "CueLive",
            dependencies: ["CueKit"],
            path: "Sources/CueLive"
        ),
        .testTarget(
            name: "CueKitTests",
            dependencies: ["CueKit"],
            path: "Tests/CueKitTests"
        ),
    ]
)
