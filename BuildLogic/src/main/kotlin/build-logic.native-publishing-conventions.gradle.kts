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

// Native-publishing convention for swift-java's classifier-bearing native artifacts
// (e.g. swiftkit-core-native, swiftkit-ffm-native).
//
// Each consuming sub-project produces ONE jar per CI run, tagged with a Maven
// classifier identifying the platform variant. The jar contains only the dylibs
// (no Java code) at the resource root, where SwiftLibraries.loadResourceLibrary
// looks them up at runtime via getResourceAsStream("/libFoo.dylib").
//
// Classifier source of truth (in priority order):
//   1. Gradle property `nativeClassifier` (set by CI to e.g. "ubuntu22.04-x86_64")
//   2. osdetector.classifier fallback for local development
//
// CI passes -PnativeClassifier=<classifier> for each matrix variant. Local
// `publishToMavenLocal` works without that flag.
//
// Each sub-project must:
//   - apply this convention
//   - set base.archivesName to the artifact id (e.g. "swiftkit-core-native")
//   - register a `nativeArtifacts` task that wires dylib paths into processResources

import com.vanniktech.maven.publish.JavaLibrary
import com.vanniktech.maven.publish.JavadocJar
import com.vanniktech.maven.publish.SourcesJar

plugins {
    `java-library`
    id("com.google.osdetector")
    id("com.vanniktech.maven.publish")
}

val nativeClassifier: String = providers.gradleProperty("nativeClassifier").orNull
    ?: osdetector.classifier

// We don't compile any Java in native sub-projects
java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(25)
    }
}

mavenPublishing {
    publishToMavenCentral(automaticRelease = false)
    signAllPublications()

    // Empty sources/javadoc jars satisfy Maven Central while reflecting that
    // these artifacts contain no source code or documentation.
    configure(
        JavaLibrary(
            javadocJar = JavadocJar.Empty(),
            sourcesJar = SourcesJar.Empty(),
        )
    )

    val scmHost: String = providers.gradleProperty("scmHost").orNull ?: ""
    val scmPath: String = providers.gradleProperty("scmPath").orNull ?: ""

    pom {
        name.set(provider { project.name })
        description.set(provider { project.description ?: "${project.name} native libraries" })
        url.set(providers.gradleProperty("projectUrl"))
        inceptionYear.set("2024")

        licenses {
            license {
                name.set("Apache License, Version 2.0")
                url.set("https://www.apache.org/licenses/LICENSE-2.0.txt")
                distribution.set("repo")
            }
        }
        developers {
            developer {
                id.set("swift-server")
                name.set("Swift.org project authors")
                url.set("https://swift.org")
            }
        }
        scm {
            url.set("https://$scmHost/$scmPath")
            connection.set("scm:git:git://$scmHost/$scmPath.git")
            developerConnection.set("scm:git:ssh://git@$scmHost/$scmPath.git")
        }
        issueManagement {
            system.set("GitHub Issues")
            url.set(providers.gradleProperty("issueManagementUrl"))
        }
        ciManagement {
            system.set("GitHub Actions")
            url.set(providers.gradleProperty("ciManagementUrl"))
        }
    }
}

// Tag every jar (and the sources/javadoc empties) with the platform classifier.
// Also stamp full netty-parity MANIFEST entries so the jars carry both standard
// JAR metadata (Implementation-*) and OSGi metadata (Bundle-NativeCode) for
// runtimes that can act on it. Per-subproject manifest entries
// (Automatic-Module-Name, Fragment-Host) are configured in the subproject build
// scripts since they are artifact-specific.
tasks.withType<Jar>().configureEach {
    archiveClassifier.set(nativeClassifier)
    manifest {
        attributes(
            "Implementation-Title" to project.name,
            "Implementation-Version" to project.version.toString(),
            "Implementation-Vendor" to "Swift.org project authors",
            "Specification-Title" to project.name,
            "Specification-Version" to project.version.toString(),
            "Specification-Vendor" to "Swift.org project authors",
            "Bundle-NativeCode" to bundleNativeCodeFor(nativeClassifier),
        )
    }
}

// Convert our Maven classifier (e.g. "osx-aarch_64", "ubuntu22.04-x86_64") into
// an OSGi Bundle-NativeCode header. OSGi only knows osname+processor, not Linux
// distro variants, so all linux-* classifiers collapse to osname=Linux. Trailing
// `,*` is OSGi syntax meaning "match this exactly OR fall back to anything".
fun bundleNativeCodeFor(classifier: String): String {
    val osname = when {
        classifier.startsWith("osx") || classifier.contains("darwin") ||
            classifier.contains("macos") -> "MacOSX"
        classifier.contains("windows") -> "Windows"
        else -> "Linux"
    }
    val processor = when {
        classifier.endsWith("-aarch_64") || classifier.endsWith("-aarch64") ||
            classifier.endsWith("-arm64") -> "aarch_64"
        classifier.endsWith("-x86_64") || classifier.endsWith("-amd64") -> "x86_64"
        else -> "unknown"
    }
    val nativeFiles = listOf(
        "META-INF/native/libSwiftRuntimeFunctions",
        "META-INF/native/libSwiftJava",
    ).map {
        when (osname) {
            "MacOSX" -> "$it.dylib"
            "Windows" -> "$it.dll"
            else -> "$it.so"
        }
    }
    return nativeFiles.joinToString("; ") + "; osname=$osname; processor=$processor,*"
}

// artifactId comes from base.archivesName (e.g. "swiftkit-core-native").
afterEvaluate {
    val archivesName = extensions.findByType<BasePluginExtension>()?.archivesName?.orNull
    if (!archivesName.isNullOrBlank()) {
        publishing.publications.withType<MavenPublication>().configureEach {
            artifactId = archivesName
        }
    }
}
