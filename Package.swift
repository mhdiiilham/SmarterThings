// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SmarterThings",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "SmarterThingsCore", linkerSettings: [.linkedFramework("IOBluetooth")]),
        .executableTarget(
            name: "SmarterThings",
            dependencies: ["SmarterThingsCore"],
            linkerSettings: [.linkedFramework("IOBluetoothUI")]
        ),
        .testTarget(name: "SmarterThingsCoreTests", dependencies: ["SmarterThingsCore"]),
    ]
)
