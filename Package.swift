// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "NiceTouch", platforms: [.macOS(.v14)],
    products: [
        .library(name: "NiceTouchCore", targets: ["NiceTouchCore"]),
        .executable(name: "ModelProbe", targets: ["ModelProbe"])
    ],
    targets: [
        .target(name: "NiceTouchCore"),
        .target(name: "NiceTouchModels", dependencies: ["NiceTouchCore"]),
        .executableTarget(name: "ModelProbe", dependencies: ["NiceTouchModels", "NiceTouchCore"]),
        .testTarget(name: "NiceTouchCoreTests", dependencies: ["NiceTouchCore"])
    ]
)
