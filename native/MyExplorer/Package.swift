// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MyExplorer",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "MyExplorer", targets: ["MyExplorer"])
    ],
    targets: [
        .executableTarget(
            name: "MyExplorer",
            path: "Sources/MyExplorer",
            resources: [
                .copy("../../Resources/MyExplorer.icns")
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuickLook"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
