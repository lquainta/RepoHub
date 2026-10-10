// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RepoHubBackend",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.121.4"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.14.0"),
        .package(url: "https://github.com/vapor/redis.git", from: "4.14.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.14.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.13.0"),
        .package(url: "https://github.com/swift-server/swift-openapi-vapor.git", from: "1.2.0"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.3.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.0"),
        .package(path: "../Packages/RepoHubCore"),
    ],
    targets: [
        // Types and server stubs generated from openapi/openapi.yaml (ADR 0008).
        .target(
            name: "RepoHubAPI",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            swiftSettings: swiftSettings,
            plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]
        ),
        .executableTarget(
            name: "App",
            dependencies: [
                .target(name: "RepoHubAPI"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIVapor", package: "swift-openapi-vapor"),
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Redis", package: "redis"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "RepoHubCore", package: "RepoHubCore"),
            ],
            // Served at /openapi.yaml; a symlink to openapi/openapi.yaml.
            resources: [.copy("Resources/openapi.yaml")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
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
