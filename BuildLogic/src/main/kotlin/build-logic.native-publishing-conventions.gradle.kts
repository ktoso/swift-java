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
// (swiftkit-core-native, swiftkit-ffm-native).
//
// Each consuming module produces ONE jar per CI run, tagged with a Maven classifier
// identifying the platform variant. The jar contains only the dylibs (no Java
// code) under META-INF/native/, where SwiftLibraries.loadResourceLibrary looks
// them up at runtime via getResourceAsStream().
//
// Classifier source of truth (in priority order):
//   1. Gradle property `nativeClassifier` (set by CI to e.g. "ubuntu22.04-x86_64")
//   2. osdetector.classifier fallback for local development
//
// Each module must:
//   - apply this convention
//   - set base.archivesName (e.g. "swiftkit-core-native")
//   - configure processResources to copy the dylibs from rootProject's
//     `compileSwiftReleaseDylibs` task output into META-INF/native/

plugins {
    `java-library`
    `maven-publish`
    id("com.google.osdetector")
}

val nativeClassifier: String = providers.gradleProperty("nativeClassifier").orNull
    ?: osdetector.classifier

java {
    toolchain { languageVersion = JavaLanguageVersion.of(25) }
}

// Empty sources/javadoc jars satisfy Maven Central's PomChecker without claiming
// there is source for the dylibs. Their classifier is composed below so they
// don't collide with main jars from other matrix entries.
val emptySourcesJar = tasks.register<Jar>("sourcesJar") {
    archiveClassifier.set("sources")
}
val emptyJavadocJar = tasks.register<Jar>("javadocJar") {
    archiveClassifier.set("javadoc")
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["java"])
            artifact(emptySourcesJar)
            artifact(emptyJavadocJar)
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
                val scmHost: String = providers.gradleProperty("scmHost").orNull ?: ""
                val scmPath: String = providers.gradleProperty("scmPath").orNull ?: ""
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
    }
    repositories {
        maven {
            url = uri(rootProject.layout.buildDirectory.dir("staging-deploy"))
        }
    }
}

// Tag every jar (main + empty sources + empty javadoc) with the platform
// classifier so they don't collide with other matrix entries' uploads. Stamp
// manifest with both standard JAR (Implementation-*) and OSGi (Bundle-NativeCode)
// metadata for runtimes that can act on it.
tasks.withType<Jar>().configureEach {
    val current = archiveClassifier.get()
    archiveClassifier.set(
        when (current) {
            "" -> nativeClassifier
            "sources" -> "$nativeClassifier-sources"
            "javadoc" -> "$nativeClassifier-javadoc"
            else -> current
        }
    )
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
