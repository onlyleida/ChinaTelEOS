// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloudBox",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "CloudBox", targets: ["CloudBox"])],
    targets: [
        .executableTarget(
            name: "CloudBox",
            path: "NativeCloudBox/Sources/CloudBox",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "CloudBoxTests",
            dependencies: ["CloudBox"],
            path: "NativeCloudBox/Tests/CloudBoxTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
