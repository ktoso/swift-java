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

// Native dylib companion to SwiftKitCore.
// Publishes per-platform classifier jars (e.g. swiftkit-core-native:VERSION:osx-aarch_64)
// containing libSwiftRuntimeFunctions and libSwiftJava at the JAR resource root.
//
// The actual `swift build` runs once at the root project (compileSwiftReleaseDylibs);
// this sub-project only packages the resulting dylibs into a classifier jar.

plugins {
    id("build-logic.native-publishing-conventions")
}

base {
    archivesName = "swiftkit-core-native"
}

description = "SwiftKit Core native libraries (libSwiftRuntimeFunctions, libSwiftJava) for use with the swiftkit-core Java module"

@Suppress("UNCHECKED_CAST")
val compileSwiftReleaseDylibs =
    rootProject.extra["compileSwiftReleaseDylibs"] as TaskProvider<Exec>
val swiftReleaseDir: File = rootProject.extra["swiftReleaseDir"] as File

// File extension comes from the classifier we'll publish under.
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
        // Match netty / OSGi convention. SwiftLibraries.loadResourceLibrary
        // checks META-INF/native/ before falling back to the JAR root.
        into("META-INF/native")
    }
}

// Per-artifact MANIFEST entries (the cross-cutting Implementation-* /
// Bundle-NativeCode entries are set by the convention plugin).
//
// Note: "native" is a Java keyword and cannot appear as a JPMS module name
// segment, so the natives jar uses ".natives" (plural) for its module name.
// Fragment-Host points at the symbolic name of the Java module this fragment
// attaches to in OSGi runtimes.
tasks.withType<Jar>().configureEach {
    manifest {
        attributes(
            "Automatic-Module-Name" to "org.swift.swiftkit.core.natives",
            "Fragment-Host" to "org.swift.swiftkit.core",
        )
    }
}
