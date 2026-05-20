// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CheTransportMCP",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.0"))
    ],
    targets: [
        .executableTarget(
            name: "CheTransportMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/CheTransportMCP",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CheTransportMCP/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "CheTransportMCPTests",
            dependencies: ["CheTransportMCP"],
            path: "Tests/CheTransportMCPTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
