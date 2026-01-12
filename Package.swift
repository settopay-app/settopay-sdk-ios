// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SettoSDK",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "SettoSDK",
            targets: ["SettoSDK"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SettoSDK",
            dependencies: [],
            path: "Sources/SettoSDK"
        )
    ]
)
