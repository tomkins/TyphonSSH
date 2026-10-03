// swift-tools-version: 6.4

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ApproachableConcurrency")
]

let package = Package(
  name: "TyphonSSH",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "tyssh", targets: ["tyssh"])
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.8.0")
  ],
  targets: [
    // Pure, platform-agnostic logic: hosts, configuration, layout, the controller state machine.
    .target(
      name: "TyphonCore",
      swiftSettings: swiftSettings
    ),
    // fork/exec and ioctl, which can't safely be called from Swift.
    .target(name: "CTyphonSupport"),
    // The macOS side: Terminal.app scripting, screens, pseudo-terminals and sockets.
    .target(
      name: "TyphonTerminal",
      dependencies: ["TyphonCore", "CTyphonSupport"],
      swiftSettings: swiftSettings
    ),
    .executableTarget(
      name: "tyssh",
      dependencies: [
        "TyphonCore",
        "TyphonTerminal",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "TyphonCoreTests",
      dependencies: ["TyphonCore"],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "TyphonTerminalTests",
      dependencies: ["TyphonTerminal"],
      swiftSettings: swiftSettings
    ),
  ]
)
