// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PocketMeshServices",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PocketMeshServices", targets: ["PocketMeshServices"])
    ],
    dependencies: [
        .package(path: "../MeshCore")
    ],
    targets: [
        .target(
            name: "PocketMeshServices",
            dependencies: ["MeshCore"]
        ),
        .testTarget(
            name: "PocketMeshServicesTests",
            dependencies: [
                "PocketMeshServices",
                .product(name: "MeshCoreTestSupport", package: "MeshCore")
            ]
        )
    ]
)
