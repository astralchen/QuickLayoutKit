// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QuickLayoutKit",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "QuickLayoutKit",
            targets: ["QuickLayoutKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/facebookincubator/QuickLayout", branch: "main"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "QuickLayoutKit",
            dependencies: [
                "QuickLayout",
                "QuickLayoutKitCore",
                "QuickLayoutKitUIKit",
            ],
            path: "Sources/QuickLayoutKit/QuickLayoutKit"
        ),
        .target(
            name: "QuickLayoutKitCore",
            dependencies: [
                "QuickLayout",
            ],
            path: "Sources/QuickLayoutKit/QuickLayoutKitCore"
        ),
        .target(
            name: "QuickLayoutKitUIKit",
            dependencies: [
                "QuickLayout",
                "QuickLayoutKitCore",
            ],
            path: "Sources/QuickLayoutKit/QuickLayoutKitUIKit"
        ),
        .testTarget(
            name: "QuickLayoutKitTests",
            dependencies: ["QuickLayoutKitCore"]
        ),
    ]
)
