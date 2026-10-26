// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MountKeeper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MountKeeper",
            swiftSettings: [.unsafeFlags(["-Osize"], .when(configuration: .release))],
            linkerSettings: [.linkedFramework("NetFS")]
        ),
        .testTarget(
            name: "MountKeeperTests",
            dependencies: ["MountKeeper"]
        ),
    ]
)
