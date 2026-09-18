// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DAYSHIFT",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DAYSHIFT", targets: ["DAYSHIFT"])
    ],
    targets: [
        .executableTarget(
            name: "DAYSHIFT",
            path: "Sources/DAYSHIFT"
        ),
        .testTarget(
            name: "DAYSHIFTTests",
            dependencies: ["DAYSHIFT"],
            path: "Tests/DAYSHIFTTests"
        )
    ]
)
