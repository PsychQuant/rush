// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Rush",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.0"))
    ],
    targets: [
        .executableTarget(
            name: "Rush",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/Rush",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/Rush/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "RushTests",
            dependencies: ["Rush"],
            path: "Tests/RushTests",
            resources: [.process("Fixtures")]
        )
    ]
)
