// swift-tools-version:6.2
import PackageDescription

/// The app's client for the RepoHub API, generated from openapi/openapi.yaml (ADR 0008).
let package = Package(
    name: "RepoHubAPIClient",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "RepoHubAPIClient", targets: ["RepoHubAPIClient"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.13.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.3.2"),
    ],
    targets: [
        .target(
            name: "RepoHubAPIClient",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            swiftSettings: swiftSettings,
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .testTarget(
            name: "RepoHubAPIClientTests",
            dependencies: ["RepoHubAPIClient"],
            swiftSettings: swiftSettings
        ),
    ]
)

var swiftSettings: [SwiftSetting] {
    [
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("MemberImportVisibility"),
    ]
}
