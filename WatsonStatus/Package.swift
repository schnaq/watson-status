// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WatsonStatus",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WatsonStatus",
            path: "Sources"
        )
    ]
)
