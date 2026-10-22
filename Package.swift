// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "NiceTouch", platforms: [.macOS(.v14)],
    products: [.executable(name: "NiceTouch", targets: ["NiceTouch"]), .executable(name: "ModelProbe", targets: ["ModelProbe"]), .library(name: "NiceTouchCore", targets: ["NiceTouchCore"])],
    targets: [
        .target(name: "NiceTouchCore"),
        .target(name: "NiceTouchModels", dependencies: ["NiceTouchCore"]),
        .target(name: "TrackpadBridge", linkerSettings: [.linkedFramework("CoreFoundation")]),
        .executableTarget(name: "NiceTouch", dependencies: ["NiceTouchCore", "NiceTouchModels", "TrackpadBridge"], resources: [.copy("Resources/mlx_worker.py"), .copy("Resources/rule.schema.json"), .copy("Resources/system-prompt.txt")]),
        .executableTarget(name: "ModelProbe", dependencies: ["NiceTouchModels", "NiceTouchCore"]),
        .testTarget(name: "NiceTouchCoreTests", dependencies: ["NiceTouchCore"]),
        .testTarget(name: "NiceTouchModelsTests", dependencies: ["NiceTouchModels", "NiceTouchCore"]),
        .testTarget(name: "NiceTouchTests", dependencies: ["NiceTouch"])
    ]
)
