// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SelectTranslate",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "SelectTranslate",
            path: "Sources/SelectTranslate"
        )
    ]
)
