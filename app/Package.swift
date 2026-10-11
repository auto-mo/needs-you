// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NeedsYou",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NeedsYou", path: "Sources/NeedsYou")
    ]
)
