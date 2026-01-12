// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "SettoSDK",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "SettoSDK",
            targets: ["SettoSDK"]
        )
    ],
    targets: [
        .target(
            name: "SettoSDK",
            path: "Sources/SettoSDK"
        )
    ]
)
