// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "MacDBG",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "macdbg-cli", targets: ["MacDBG-CLI"]),
        .library(name: "MacDBG", targets: ["MacDBG"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacDBG-CLI",
            dependencies: ["MacDBG"],
            path: "cli",
            exclude: ["build.sh"]
        ),
        .target(
            name: "MacDBG",
            path: "src",
            exclude: ["MacDBGApp.swift", "DebuggerViews.swift", "TestTarget.c"]
        )
    ]
)
