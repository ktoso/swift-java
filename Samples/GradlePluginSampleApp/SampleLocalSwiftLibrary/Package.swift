// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "SampleLocalSwiftLibrary",
  platforms: [
    .macOS(.v15)
  ],
  products: [
    .library(
      name: "SampleLocalSwiftLibrary",
      type: .dynamic,
      targets: ["SampleLocalSwiftLibrary"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-log.git", from: "1.6.3")
  ],
  targets: [
    .target(
      name: "SampleLocalSwiftLibrary",
      dependencies: [
        .product(name: "Logging", package: "swift-log")
      ],
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ]
    )
  ]
)
