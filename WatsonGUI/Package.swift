// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WatsonGUI",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WatsonGUI",
            path: "Sources"
        )
    ]
)
