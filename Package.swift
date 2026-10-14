// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Todaytape",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Todaytape",
            path: "Sources/Todaytape",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("ServiceManagement")]
        )
    ]
)
