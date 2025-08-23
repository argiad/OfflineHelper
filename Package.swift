// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RequestRelayKit",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        // Main library product - Complete framework
        .library(
            name: "RequestRelayKit",
            targets: ["RequestRelayKit"]
        ),
        
    ],
    dependencies: [],
    targets: [
	// Complete framework
	.target(
            name: "RequestRelayKit",
            dependencies: [],
            path: "RequestRelayKit/Sources",
            exclude: ["Info.plist"],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("RELEASE", .when(configuration: .release)),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    
    ],
    swiftLanguageModes: [.v6]
)
