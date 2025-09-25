// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PulsarTesting",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "pulsar-load-test",
            targets: ["PulsarLoadTest"]
        )
    ],
    dependencies: [
        // TODO: replace with url
        .package(path: "../PulsarClient"),
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.4.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.6.3"),
        .package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.1.0")
    ],
    targets: [
        .executableTarget(
            name: "PulsarLoadTest",
            dependencies: [
                .product(name: "PulsarClient", package: "PulsarClient"),
                .product(name: "Metrics", package: "swift-metrics"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Prometheus", package: "swift-prometheus"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Tracing", package: "swift-distributed-tracing")
            ],
        ),
        .testTarget(
            name: "PulsarLoadTestTests",
            dependencies: ["PulsarLoadTest"]
        )
    ],
    swiftLanguageModes: [.v6]
)