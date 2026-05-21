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

import utilities.javaLibraryPaths
import java.io.File

plugins {
    java
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of((gradle.extra.properties["swiftJavaJdk"] as? Int) ?: 25)
    }
}

repositories {
    mavenCentral()
}

// Configure paths for native (Swift) libraries
tasks.test {
    jvmArgs(
        "--enable-native-access=ALL-UNNAMED",

        // Include the library paths where our dylibs are that we want to load and call
        "-Djava.library.path=" + project.javaLibraryPaths(project.projectDir).joinToString(File.pathSeparator)
    )
}

tasks.withType<Test> {
    this.testLogging {
        this.showStandardStreams = true
    }
}

// Validate javadoc for html/syntax/reference correctness but skip "missing" (no comment) warnings
tasks.withType<Javadoc> {
    (options as StandardJavadocDocletOptions).addStringOption("Xdoclint:all,-missing", "-quiet")
}
