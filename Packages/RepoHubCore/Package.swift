// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RepoHubCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "RepoHubCore", targets: ["RepoHubCore"])
    ],
    targets: [
        .target(
            name: "RepoHubCore",
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RepoHubCoreTests",
            dependencies: ["RepoHubCore"],
            exclude: ["Fixtures/generate-fixtures.sh"],
            resources: [.copy("Fixtures/git-output")],
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
