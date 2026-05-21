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

import org.jreleaser.model.Active

plugins {
    base
    id("org.jreleaser") version "1.24.0"
}

// ==== ----------------------------------------------------------------------
// MARK: Project version (derived from git tags)
// ==== ----------------------------------------------------------------------
//
// Rules:
//   - HEAD is exactly at a tag matching N.N.N -> version = that tag (release)
//   - Otherwise                               -> latest tag patch+1 + "-SNAPSHOT"
//   - No tags at all                          -> "0.0.1-SNAPSHOT"
//
// CI checkouts must use `fetch-depth: 0` (or fetch tags explicitly) so this
// can see the tag history.

val tagPattern = Regex("""^\d+\.\d+\.\d+$""")

fun runGit(vararg args: String): String? = try {
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

group = providers.gradleProperty("group").get()

// Helper for CI: `./gradlew -q printVersion` prints the resolved version
tasks.register("printVersion") {
    doLast { println(computedVersion) }
}

// ==== ----------------------------------------------------------------------
// MARK: Shared Swift dylib build (consumed by SwiftKit*Native modules)
// ==== ----------------------------------------------------------------------
//
// Both SwiftKitCoreNative and SwiftKitFFMNative bundle the SAME set of dylibs
// (libSwiftRuntimeFunctions, libSwiftJava) into their classifier jars. We build
// them once here to avoid Gradle's "two parallel tasks targeting same output
// directory" validation error.
//
// CI may pass `-PnativeBuildSdk=<sdk>` to add `--swift-sdk <sdk>` to the
// invocation (e.g. for the Swift static-linux SDK). Output then moves to
// .build/<sdk>/release/.

val nativeBuildSdk: String? = providers.gradleProperty("nativeBuildSdk").orNull

val swiftReleaseDir: File = if (nativeBuildSdk != null) {
    File(rootDir, ".build/$nativeBuildSdk/release")
} else {
    File(rootDir, ".build/release")
}

val compileSwiftRuntimeFunctionsRelease = tasks.register<Exec>("compileSwiftRuntimeFunctionsRelease") {
    description = "Build libSwiftRuntimeFunctions dynamic library (release config)"
    group = "swift"
    workingDir = rootDir
    commandLine = swiftBuildCommand("SwiftRuntimeFunctions")
    inputs.file(File(rootDir, "Package.swift"))
    inputs.dir(File(rootDir, "Sources/SwiftRuntimeFunctions"))
    outputs.file(File(swiftReleaseDir, "libSwiftRuntimeFunctions.dylib"))
}

val compileSwiftJavaRelease = tasks.register<Exec>("compileSwiftJavaRelease") {
    description = "Build libSwiftJava dynamic library (release config)"
    group = "swift"
    workingDir = rootDir
    commandLine = swiftBuildCommand("SwiftJava")
    inputs.file(File(rootDir, "Package.swift"))
    inputs.dir(File(rootDir, "Sources"))
    outputs.file(File(swiftReleaseDir, "libSwiftJava.dylib"))
}

// Aggregator: invokes both per-product Exec tasks. We split them because
// `swift build --product A --product B` only builds the *last* product (SwiftPM
// quirk as of Swift 6.3.1). Running two separate invocations is the workaround.
val compileSwiftReleaseDylibs = tasks.register("compileSwiftReleaseDylibs") {
    description = "Build SwiftRuntimeFunctions and SwiftJava dynamic libraries (release config)"
    group = "swift"
    dependsOn(compileSwiftRuntimeFunctionsRelease, compileSwiftJavaRelease)
}

fun swiftBuildCommand(product: String): List<String> {
    val base = mutableListOf(
        "swift", "build",
        "--disable-experimental-prebuilts",
        "-c", "release",
        "--product", product,
    )
    nativeBuildSdk?.let { base += listOf("--swift-sdk", it) }
    return base
}

extra["swiftReleaseDir"] = swiftReleaseDir

// ==== ----------------------------------------------------------------------
// MARK: Aggregate task to stage every publishable module to build/staging-deploy
// ==== ----------------------------------------------------------------------
//
// `./gradlew stageForJReleaser` runs `:Module:publish` for every publishable
// module so they all land in the shared `<root>/build/staging-deploy/` directory
// that JReleaser consumes via `./gradlew jreleaserDeploy`.
//
// Native modules are wired conditionally: when JDK < 22 they aren't part of
// the build (see settings.gradle.kts gating).

tasks.register("stageForJReleaser") {
    description = "Publishes all Java + native modules to the local staging directory consumed by JReleaser."
    group = "publishing"
    val publishableModules = listOf(
        ":SwiftKitCore",
        ":SwiftKitCoreNative",
        ":SwiftKitFFM",
        ":SwiftKitFFMNative",
    )
    publishableModules.forEach { modulePath ->
        if (rootProject.findProject(modulePath) != null) {
            dependsOn("$modulePath:publish")
        }
    }
}

// ==== ----------------------------------------------------------------------
// MARK: JReleaser configuration
// ==== ----------------------------------------------------------------------
//
// Mirrors the official Sonatype + JReleaser dual-deployer pattern at
//   https://jreleaser.org/guide/latest/examples/maven/maven-central.html
//
// Two deployers, routed by the project version's -SNAPSHOT suffix:
//   - mavenCentral.release-deploy  (active = RELEASE)  -> Portal Publisher API
//                                                          for non-SNAPSHOT
//   - nexus2.snapshot-deploy       (active = SNAPSHOT) -> Central Portal
//                                                          snapshots repo
//
// CI workflow:
//   1. ./gradlew stageForJReleaser   # writes jars + POMs to build/staging-deploy
//   2. ./gradlew jreleaserDeploy     # signs, validates, uploads
//
// Required env vars on CI:
//   JRELEASER_GPG_PUBLIC_KEY, JRELEASER_GPG_SECRET_KEY, JRELEASER_GPG_PASSPHRASE
//   JRELEASER_MAVENCENTRAL_USERNAME / _PASSWORD  (release path)
//   JRELEASER_NEXUS2_USERNAME / _PASSWORD        (snapshot path)
//
// Local dev: leave the env vars unset and JReleaser stays inert. `./gradlew
// stageForJReleaser` still works; `./gradlew jreleaserDeploy` will fail loudly.

jreleaser {
    project {
        description.set("Swift/Java interoperability runtime libraries")
        copyright.set("Copyright (c) 2024 Apple Inc. and the Swift.org project authors")
        license.set("Apache-2.0")
        links { homepage.set(providers.gradleProperty("projectUrl")) }
    }
    // We only use JReleaser for deployment — not for cutting GitHub Releases or
    // pushing tags. This block satisfies JReleaser's required `release` section
    // without doing anything at release time.
    release {
        github {
            skipRelease.set(true)
            skipTag.set(true)
            // Token is required by validation even though skipRelease/skipTag are on.
            // Real CI sets JRELEASER_GITHUB_TOKEN; locally a dummy is fine.
            token.set(providers.environmentVariable("JRELEASER_GITHUB_TOKEN").orElse("dummy"))
            // Match the project's actual repo so SCM-derived metadata is correct.
            repoOwner.set("swiftlang")
            name.set("swift-java")
        }
    }
    signing {
        active.set(Active.ALWAYS)
        armored.set(true)
        // mode defaults to MEMORY; reads JRELEASER_GPG_{PUBLIC_KEY,SECRET_KEY,PASSPHRASE} from env
    }
    deploy {
        maven {
            mavenCentral {
                create("release-deploy") {
                    active.set(Active.RELEASE)
                    url.set("https://central.sonatype.com/api/v1/publisher")
                    stagingRepository("build/staging-deploy")
                    // applyMavenCentralRules is enabled automatically for the mavenCentral deployer.
                    // Deployments land in USER_MANAGED state by default — finalize at
                    // https://central.sonatype.com/publishing/deployments
                }
            }
            nexus2 {
                create("snapshot-deploy") {
                    active.set(Active.SNAPSHOT)
                    snapshotUrl.set("https://central.sonatype.com/repository/maven-snapshots/")
                    applyMavenCentralRules.set(true)
                    snapshotSupported.set(true)
                    closeRepository.set(true)
                    releaseRepository.set(true)
                    stagingRepository("build/staging-deploy")
                }
            }
        }
    }
}
