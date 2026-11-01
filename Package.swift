// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ledge",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ledge",
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
