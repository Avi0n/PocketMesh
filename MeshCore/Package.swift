// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeshCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MeshCore",
            targets: ["MeshCore"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MeshCore"
        ),
        .testTarget(
            name: "MeshCoreTests",
            dependencies: ["MeshCore"]
        )
    ]
)
