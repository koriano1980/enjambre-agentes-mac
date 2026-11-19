// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Enjambre",
    products: [
        .library(name: "EnjambreNucleo", targets: ["EnjambreNucleo"]),
        .executable(name: "Enjambre", targets: ["EnjambreApp"]),
    ],
    targets: [
        .target(name: "EnjambreNucleo"),
        .executableTarget(
            name: "EnjambreApp",
            dependencies: ["EnjambreNucleo"],
            linkerSettings: [
                .linkedFramework("Carbon", .when(platforms: [.macOS])),
                .linkedFramework("ApplicationServices", .when(platforms: [.macOS])),
                .linkedFramework("Speech", .when(platforms: [.macOS])),
                .linkedFramework("AVFoundation", .when(platforms: [.macOS])),
                .linkedFramework("CoreGraphics", .when(platforms: [.macOS])),
                .linkedFramework("Network", .when(platforms: [.macOS])),
                .linkedFramework("Vision", .when(platforms: [.macOS])),
                .linkedFramework("WebKit", .when(platforms: [.macOS])),
            ]
        ),
        .testTarget(
            name: "EnjambreNucleoTests",
            dependencies: ["EnjambreNucleo"]
        ),
    ]
)
