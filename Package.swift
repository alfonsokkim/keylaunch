// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyLaunch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "KeyLaunch", path: "Sources/KeyLaunch")
    ]
)
