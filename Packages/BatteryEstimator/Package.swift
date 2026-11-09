// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BatteryEstimator",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "BatteryEstimator", targets: ["BatteryEstimator"]),
    ],
    targets: [
        .target(name: "BatteryEstimator"),
        .testTarget(name: "BatteryEstimatorTests", dependencies: ["BatteryEstimator"]),
    ],
    swiftLanguageVersions: [.v5]
)
