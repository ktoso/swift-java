//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024-2026 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

// Compute the project version from git tags
//
// Rules:
//   - HEAD is exactly at a tag matching N.N.N  -> version = that tag (release)
//   - Otherwise                                -> version = (latest tag, patch+1) + "-SNAPSHOT"
//   - No tags at all                           -> "0.0.1-SNAPSHOT"
//
// CI checkouts must use `fetch-depth: 0` (or fetch tags explicitly) so this
// can see the tag history.

val tagPattern = Regex("""^\d+\.\d+\.\d+$""")

fun runGit(vararg args: String): String? {
    return try {
        val process = ProcessBuilder("git", *args)
            .directory(rootDir)
            .redirectErrorStream(false)
            .start()
        val out = process.inputStream.bufferedReader().readText().trim()
        process.errorStream.bufferedReader().readText() // drain
        if (process.waitFor() == 0 && out.isNotEmpty()) out else null
    } catch (_: Exception) {
        null
    }
}

fun computeVersion(): String {
    val exact = runGit("describe", "--exact-match", "--tags", "HEAD")
    if (exact != null && tagPattern.matches(exact)) {
        return exact
    }

    val latest = runGit("describe", "--tags", "--abbrev=0")
    val (major, minor, patch) = if (latest != null && tagPattern.matches(latest)) {
        latest.split(".").map { it.toInt() }
    } else {
        listOf(0, 0, 0)
    }
    return "$major.$minor.${patch + 1}-SNAPSHOT"
}

val computedVersion: String = computeVersion()

allprojects {
    version = computedVersion
}

// Helper for CI: `./gradlew -q printVersion` prints the resolved version
tasks.register("printVersion") {
    doLast { println(computedVersion) }
}

// ==== ----------------------------------------------------------------------
// Shared Swift dylib build (consumed by SwiftKitCoreNative and SwiftKitFFMNative)
// ==== ----------------------------------------------------------------------
//
// The native sub-projects both bundle the SAME set of dylibs (currently
// libSwiftRuntimeFunctions and libSwiftJava) into their classifier jars. Only
// build them once here to avoid Gradle's "implicit dependency on shared output
// directory" validation error from two parallel tasks targeting .build/release/.
//
// CI may pass `-PnativeBuildSdk=<sdk>` to add `--swift-sdk <sdk>` to the
// invocation (e.g. for the Swift static-linux SDK to produce the linux-unknown
// classifier). Output then moves to .build/<sdk>/release/.

val nativeBuildSdk: String? = providers.gradleProperty("nativeBuildSdk").orNull

val swiftReleaseDir: File = if (nativeBuildSdk != null) {
    File(rootDir, ".build/$nativeBuildSdk/release")
} else {
    File(rootDir, ".build/release")
}

val compileSwiftReleaseDylibs = tasks.register<Exec>("compileSwiftReleaseDylibs") {
    description = "Build SwiftRuntimeFunctions and SwiftJava dynamic libraries (release config)"
    group = "swift"
    workingDir = rootDir
    commandLine("swift")
    val swiftArgs = mutableListOf(
        "build",
        "--disable-experimental-prebuilts",
        "-c", "release",
        "--product", "SwiftRuntimeFunctions",
        "--product", "SwiftJava",
    )
    nativeBuildSdk?.let { swiftArgs += listOf("--swift-sdk", it) }
    args(swiftArgs)

    inputs.file(File(rootDir, "Package.swift"))
    inputs.dir(File(rootDir, "Sources"))
    outputs.dir(swiftReleaseDir)
}

// Expose the resolved release dir for the natives sub-projects to consume.
extra["swiftReleaseDir"] = swiftReleaseDir
extra["compileSwiftReleaseDylibs"] = compileSwiftReleaseDylibs
