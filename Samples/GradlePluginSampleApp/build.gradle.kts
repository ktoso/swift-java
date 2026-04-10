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
    id("build-logic.java-application-conventions")
    id("swift-java-plugin")
}

group = "org.swift.swiftkit"
version = "1.0-SNAPSHOT"

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(25))
    }
}

dependencies {
    implementation(projects.swiftKitCore)
    implementation(projects.swiftKitFFM)

    testRuntimeOnly(libs.junit.platform.launcher)
    testImplementation(platform(libs.junit.bom))
    testImplementation(libs.junit.jupiter)
}

tasks.named<Test>("test") {
    useJUnitPlatform()
}

application {
    mainClass = "com.example.swift.JavaAppSampleMain"
}

swiftDependencies {
    swiftPackage(
        url = "https://github.com/apple/swift-log.git",
        version = "1.6.3",
        products = listOf("Logging")
    )

    swiftPackage(
        path = file("SampleLocalSwiftLibrary"),
        products = listOf("SampleLocalSwiftLibrary")
    )
}
