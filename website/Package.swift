// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PinShellWebsite",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .executableTarget(
            name: "TemplateCatalogBuilder",
            dependencies: [
                .product(name: "PinShellCore", package: "PinShell")
            ],
            path: "Sources/TemplateCatalogBuilder"
        )
    ]
)
