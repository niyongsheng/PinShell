// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PinShell",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PinShell",
            path: "Sources/PinShell"
        )
    ]
)
