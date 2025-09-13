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
            exclude: [
                "MacDBGApp.swift", 
                "DebuggerViews.swift", 
                "TestTarget.c",
                "DebuggerController_broken.swift",
                "DebuggerController_old.swift", 
                "DebuggerControllerFixed.swift",
                "DisassemblyView_Basic.swift",
                "DisassemblyView_Basic2.swift",
                "DisassemblyView_Complex2.swift",
                "DisassemblyView_Complex.swift",
                "DisassemblyView_Minimal.swift",
                "DisassemblyView_Minimal2.swift",
                "DisassemblyView_Simple.swift",
                "DisassemblyView_UltraSimple.swift",
                "MinimalContentView.swift",
                "MinimalDebuggerController.swift",
                "DisassemblyView.swift.backup"
            ],
            resources: [
                .process("../../models")
            ]
        )
    ]
)
