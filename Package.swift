// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UntoldGaussianTwins",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "UntoldGaussianTwins", targets: ["UntoldGaussianTwins"]),
    ],
    dependencies: [
        // The mesh occluder shell, mesh fade, gaussianAsset link and URL splat loader this
        // package builds on are on the fork's develop until upstream ships them.
        .package(url: "https://github.com/untoldengine/UntoldEngine.git", branch: "develop"),
    ],
    // Sources/UntoldGaussianTwinsEditor is deliberately not a target: only the Untold editor
    // compiles it, against its own engine, as untold-package.json tells it to.
    targets: [
        .target(
            name: "UntoldGaussianTwins",
            dependencies: [
                .product(name: "UntoldEngine", package: "UntoldEngine"),
            ]
        ),
        .testTarget(
            name: "UntoldGaussianTwinsTests",
            dependencies: ["UntoldGaussianTwins"],
            resources: [.copy("Resources")]
        ),
    ]
)
