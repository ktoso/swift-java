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

// Native dylib companion to SwiftKitFFM.
// Publishes per-platform classifier jars (e.g. swiftkit-ffm-native:VERSION:osx-aarch_64)
// containing libSwiftRuntimeFunctions and libSwiftJava at the JAR resource root.
//
// The dylib contents are currently identical to swiftkit-core-native; the two
// artifacts are kept distinct so each Java module can evolve its native surface
// independently in the future.
//
// The actual `swift build` runs once at the root project (compileSwiftReleaseDylibs);
// this sub-project only packages the resulting dylibs into a classifier jar.

plugins {
    id("build-logic.native-publishing-conventions")
}

base {
    archivesName = "swiftkit-ffm-native"
}

description = "SwiftKit FFM native libraries (libSwiftRuntimeFunctions, libSwiftJava) for use with the swiftkit-ffm Java module"

@Suppress("UNCHECKED_CAST")
val compileSwiftReleaseDylibs =
    rootProject.extra["compileSwiftReleaseDylibs"] as TaskProvider<Exec>
val swiftReleaseDir: File = rootProject.extra["swiftReleaseDir"] as File

val nativeClassifierForExt: String =
    providers.gradleProperty("nativeClassifier").orNull ?: osdetector.classifier
val nativeLibExtension: String = when {
    nativeClassifierForExt.contains("osx") || nativeClassifierForExt.contains("darwin") ||
        nativeClassifierForExt.contains("macos") -> "dylib"
    nativeClassifierForExt.contains("windows") -> "dll"
    else -> "so"
}

tasks.processResources.configure {
    dependsOn(compileSwiftReleaseDylibs)
    from(swiftReleaseDir) {
        include("libSwiftRuntimeFunctions.$nativeLibExtension")
        include("libSwiftJava.$nativeLibExtension")
    }
}
