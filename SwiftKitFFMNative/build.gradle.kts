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

// Per-platform native dylibs that swiftkit-ffm needs at runtime. Published as a
// classifier jar (e.g. swiftkit-ffm-native-<version>-osx-aarch_64.jar) carrying
// libSwiftRuntimeFunctions and libSwiftJava under META-INF/native/.

plugins {
    id("build-logic.native-swift-publishing-conventions")
}

base {
    archivesName = "swiftkit-ffm-native"
}
description = "Swift native dynamic libraries needed by swiftkit-ffm at runtime."

val swiftReleaseDir = rootProject.extra["swiftReleaseDir"] as File

tasks.processResources {
    dependsOn(rootProject.tasks.named("compileSwiftReleaseDylibs"))
    from(swiftReleaseDir) {
        include("libSwiftRuntimeFunctions.dylib", "libSwiftRuntimeFunctions.so")
        include("libSwiftJava.dylib", "libSwiftJava.so")
        into("META-INF/native")
    }
}
