// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "HermlandCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "HermlandCore", targets: ["HermlandCore"])],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio-ssh.git", exact: "0.13.0"),
        .package(url: "https://github.com/apple/swift-nio-transport-services.git", exact: "1.27.0"),
    ],
    targets: [
        .target(name: "HermlandCore", dependencies: [
            .product(name: "NIOSSH", package: "swift-nio-ssh"),
            .product(name: "NIOTransportServices", package: "swift-nio-transport-services"),
        ], path: "shared"),
        .testTarget(name: "HermlandCoreTests", dependencies: ["HermlandCore"], path: "ios/Tests/Core"),
    ],
    swiftLanguageModes: [.v5]
)
