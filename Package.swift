// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "NiceTouch", platforms: [.macOS(.v14)],
    products: [
        .library(name: "NiceTouchCore", targets: ["NiceTouchCore"])
    ],
    targets: [
        .target(name: "NiceTouchCore")
    ]
)
