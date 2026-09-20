// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmartCopyPaste",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "SCPKit", path: "Sources/SCPKit"),
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
