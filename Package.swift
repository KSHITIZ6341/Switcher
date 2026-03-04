// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SidebarPin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SidebarPin", targets: ["SidebarPin"])
    ],
    targets: [
        .executableTarget(
            name: "SidebarPin"
        ),
        .testTarget(
            name: "SidebarPinTests",
            dependencies: ["SidebarPin"]
        )
    ]
)
