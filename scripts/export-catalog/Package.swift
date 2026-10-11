// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ExportCatalog",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../ios/Packages/AppCore")],
    targets: [
        .executableTarget(name: "ExportCatalog", dependencies: [.product(name: "AppCore", package: "AppCore")]),
    ]
)
