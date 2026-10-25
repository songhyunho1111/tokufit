// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "REPickShared",
    defaultLocalization: "ko",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "REPickShared", targets: ["REPickShared"])],
    targets: [
        .target(name: "REPickShared", resources: [.process("Resources")]),
        .testTarget(name: "REPickSharedTests", dependencies: ["REPickShared"])
    ]
)
