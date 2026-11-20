// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PinShell",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "PinShellCore",
            path: "Sources/PinShellCore"
        ),
        .executableTarget(
            name: "PinShell",
            dependencies: ["PinShellCore"],
            path: "Sources/PinShell"
        ),
        .testTarget(
            name: "PinShellCoreTests",
            dependencies: ["PinShellCore"],
            path: "Tests/PinShellCoreTests"
        )
    ]
)
