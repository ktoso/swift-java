// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

// PoC sample: implement the client protocol from
// https://github.com/apple/swift-http-api-proposal on top of
// java.net.HttpURLConnection via swift-java's JNI wrapper generation.
//
// The proposal package targets only Apple platforms and uses experimental
// features (~Copyable / ~Escapable / LifetimeDependence / typed throws /
// AsyncStreaming via swift-async-algorithms's UnstableAsyncStreaming trait),
// so the matching package settings are mirrored on the consumer target below.
let package = Package(
  name: "JavaNetHTTPClient",
  platforms: [
    .macOS(.v15),
    .iOS(.v18),
    .watchOS(.v11),
    .tvOS(.v18),
  ],

  products: [
    .library(
      name: "JavaNetHTTPClient",
      targets: ["JavaNetHTTPClient"]
    ),
    .executable(
      name: "JavaNetHTTPClientDemo",
      targets: ["JavaNetHTTPClientDemo"]
    ),
  ],

  dependencies: [
    .package(name: "swift-java", path: "../../"),
    .package(path: "../../../swift-http-api-proposal"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.5.1"),
    .package(url: "https://github.com/apple/swift-distributed-tracing.git", from: "1.4.1"),
  ],

  targets: [
    .target(
      name: "JavaNetHTTPClient",
      dependencies: [
        .product(name: "SwiftJava", package: "swift-java"),
        .product(name: "JavaNet", package: "swift-java"),
        .product(name: "JavaIO", package: "swift-java"),
        .product(name: "HTTPAPIs", package: "swift-http-api-proposal"),
        .product(name: "BasicContainers", package: "swift-collections"),
        .product(name: "Tracing", package: "swift-distributed-tracing"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v5),
        .strictMemorySafety(),
        .enableExperimentalFeature("SuppressedAssociatedTypesWithDefaults"),
        .enableExperimentalFeature("LifetimeDependence"),
        .enableExperimentalFeature("Lifetimes"),
        .enableUpcomingFeature("LifetimeDependence"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableUpcomingFeature("InferIsolatedConformances"),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("MemberImportVisibility"),
      ],
      plugins: [
        .plugin(name: "SwiftJavaPlugin", package: "swift-java")
      ]
    ),
    .executableTarget(
      name: "JavaNetHTTPClientDemo",
      dependencies: [
        "JavaNetHTTPClient",
        .product(name: "SwiftJava", package: "swift-java"),
        .product(name: "HTTPAPIs", package: "swift-http-api-proposal"),
        .product(name: "BasicContainers", package: "swift-collections"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v5)
      ]
    ),
  ]
)
