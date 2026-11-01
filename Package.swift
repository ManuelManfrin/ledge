// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "trackpad-bordi",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "volume-bordo",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
