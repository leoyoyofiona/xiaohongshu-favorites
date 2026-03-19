// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "XHSOrganizer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "XHSOrganizerCore",
            targets: ["XHSOrganizerCore"]
        ),
        .executable(
            name: "XHSOrganizerApp",
            targets: ["XHSOrganizerApp"]
        ),
        .executable(
            name: "XHSOrganizerCoreCheck",
            targets: ["XHSOrganizerCoreCheck"]
        )
    ],
    targets: [
        .target(
            name: "XHSOrganizerCore",
            path: "Sources/XHSOrganizerCore"
        ),
        .executableTarget(
            name: "XHSOrganizerApp",
            dependencies: ["XHSOrganizerCore"],
            path: "Sources/XHSOrganizerApp"
        ),
        .executableTarget(
            name: "XHSOrganizerCoreCheck",
            dependencies: ["XHSOrganizerCore"],
            path: "Tests/XHSOrganizerAppTests"
        )
    ]
)
