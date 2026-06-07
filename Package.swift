// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TodoSticky",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TodoCore", targets: ["TodoCore"]),
        .executable(name: "TodoSticky", targets: ["TodoApp"])
    ],
    targets: [
        .target(
            name: "TodoCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "TodoApp",
            dependencies: ["TodoCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "TodoCoreTests",
            dependencies: ["TodoCore"]
        )
    ]
)
