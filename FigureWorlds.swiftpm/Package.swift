// swift-tools-version: 5.9

// Figure Worlds: an App Playground. Open this folder in Xcode (File > Open)
// or in Swift Playgrounds on iPad/Mac, then run it on an iPhone or iPad.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Figure Worlds",
    platforms: [
        .iOS("18.0")
    ],
    products: [
        .iOSApplication(
            name: "Figure Worlds",
            targets: ["AppModule"],
            bundleIdentifier: "app.figureshelf.FigureWorlds",
            teamIdentifier: "B6LBNVRNQ4",
            displayVersion: "0.1",
            bundleVersion: "1",
            appIcon: .asset("AppIcon"),
            accentColor: .presetColor(.green),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight(.when(deviceFamilies: [.pad, .phone])),
                .landscapeLeft(.when(deviceFamilies: [.pad, .phone])),
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            path: ".",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
