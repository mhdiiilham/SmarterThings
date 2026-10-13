// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TVRemote",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "TVRemoteCore"),
        .executableTarget(name: "TVRemoteApp", dependencies: ["TVRemoteCore"]),
        .testTarget(name: "TVRemoteCoreTests", dependencies: ["TVRemoteCore"]),
    ]
)
