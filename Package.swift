// swift-tools-version: 6.2
// swift-tools-version 声明构建此软件包所需的最低 Swift 版本。

import PackageDescription

let package = Package(
    name: "QuickLayoutKit",
    platforms: [
        .iOS(.v15),
    ],
    products: [
        // 产品定义软件包生成并向其他软件包公开的可执行文件和库。
        .library(
            name: "QuickLayoutKit",
            targets: ["QuickLayoutKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/facebookincubator/QuickLayout",
            revision: "62310c0a7f4ec43f3ea6ff89f3824ef6b23b2bb3"
        ),
    ],
    targets: [
        // 目标是软件包的基本构成单元，用于定义模块或测试套件。
        // 目标可以依赖软件包中的其他目标以及依赖项提供的产品。
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
            dependencies: ["QuickLayoutKitCore", "QuickLayoutKitUIKit"]
        ),
    ]
)
