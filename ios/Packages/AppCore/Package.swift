// swift-tools-version:5.9
import PackageDescription

// Platform-independent business logic shared by the iOS app.
// Everything in here builds and tests on Linux too (`swift test`), so keep it
// free of UIKit/SwiftUI/ImageIO imports.
let package = Package(
    name: "AppCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AppCore", targets: ["AppCore"]),
    ],
    targets: [
        .target(name: "AppCore"),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
    ]
)
