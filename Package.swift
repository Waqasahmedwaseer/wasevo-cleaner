// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WasevoCleaner",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WasevoCleaner", path: "Sources/WasevoCleaner"),
    ]
)
