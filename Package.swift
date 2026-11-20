// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ynab-mcp",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "ynab-mcp", targets: ["ynab-mcp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", from: "0.12.1"),
        .package(url: "https://github.com/andrebocchini/swiftynab", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "YNABMCPLib",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "SwiftYNAB", package: "swiftynab"),
            ],
            path: "Sources/YNABMCPLib"
        ),
        .executableTarget(
            name: "ynab-mcp",
            dependencies: ["YNABMCPLib"],
            path: "Sources/ynab-mcp"
        ),
        .testTarget(
            name: "YNABMCPTests",
            dependencies: [
                "YNABMCPLib",
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
    ]
)
