// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "GraalSample",
  products: [
    .executable(
      name: "GraalSample",
      targets: ["GraalSample"]
    )
  ],
  targets: [
    .executableTarget(
      name: "GraalSample",
      dependencies: ["JEnvMap"],
      linkerSettings: [
        .unsafeFlags(["-lenvmap"])
      ]
    ),
    .target(
      name: "JEnvMap"
    ),
  ]
)
