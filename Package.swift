// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SmarterThings",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "SmarterThingsCore"),
        .executableTarget(name: "SmarterThings", dependencies: ["SmarterThingsCore"]),
        .testTarget(name: "SmarterThingsCoreTests", dependencies: ["SmarterThingsCore"]),
    ]
)
