//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

plugins {
    `kotlin-dsl`
    embeddedKotlin("plugin.serialization")
}

repositories {
    gradlePluginPortal()
    mavenCentral()
}

dependencies {
    implementation(libs.kotlinx.serialization.json)

    // Lets build-logic.published-library-conventions.gradle.kts apply
    // id("com.google.osdetector") without a version (precompiled script plugins can
    // only apply plugins already on this build's own classpath)
    implementation("com.google.gradle:osdetector-gradle-plugin:1.7.3")
}