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
      swiftSettings: [
        .unsafeFlags(["-I/Users/ktoso/code/swift-java/graal/lib"])
      ],
      linkerSettings: [
        .unsafeFlags(["-I/Users/ktoso/code/swift-java/graal/lib", "-lenvmap", ])
      ]
    ),
    .target(
      name: "JEnvMap"
    ),
  ]
)
