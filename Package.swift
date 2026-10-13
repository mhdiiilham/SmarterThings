// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SmarterThings",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SmarterThingsCore"),
        .executableTarget(name: "SmarterThings", dependencies: ["SmarterThingsCore"]),
        .testTarget(name: "SmarterThingsCoreTests", dependencies: ["SmarterThingsCore"]),
    ]
)
