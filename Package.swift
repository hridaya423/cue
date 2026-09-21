// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartCopyPaste",
    platforms: [.macOS(.v15)],
    dependencies: [
        // On-device PII redaction (11.6 MB Core ML model, downloads on demand).
        // Pinned to 3.1.x: v3.2.0 is fresh — let it bake.
        .package(url: "https://github.com/Desert-Ant-Labs/desert-ant-core.git",
                 .upToNextMinor(from: "3.1.0")),
    ],
    targets: [
        .target(
            name: "SCPKit",
            dependencies: [.product(name: "Redact", package: "desert-ant-core")],
            path: "Sources/SCPKit"
        ),
        .executableTarget(
            name: "SmartCopyPaste",
            dependencies: ["SCPKit"],
            path: "Sources/SmartCopyPaste"
        ),
        .testTarget(
            name: "SCPKitTests",
            dependencies: ["SCPKit"],
            path: "Tests/SCPKitTests"
        ),
    ]
)
