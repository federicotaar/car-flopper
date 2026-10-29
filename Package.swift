// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CarFlopper",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "CarFlopper", targets: ["CarFlopper"])
    ],
    targets: [
        .target(name: "CarFlopper")
    ],
    swiftLanguageModes: [.v5]
)
