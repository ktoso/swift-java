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

// Publishing convention for swift-java's Java libraries (SwiftKitCore, SwiftKitFFM).
//
// Each subproject that applies this convention publishes a single MavenPublication
// named "maven" containing the main jar, sources jar, and javadoc jar. Artifacts
// land in the shared local directory `<rootDir>/build/staging-deploy/` from where
// JReleaser (configured at the root) picks them up and uploads to Sonatype.
//
// The artifactId is taken from `base.archivesName` so that e.g. SwiftKitCore (the
// Gradle project) publishes as `swiftkit-core` (the Maven artifact).

plugins {
    // `java` is idempotent — re-applying it on top of `application` is fine.
    // It gives us type-safe access to `withSourcesJar()` / `withJavadocJar()`.
    java
    `maven-publish`
}

java {
    withSourcesJar()
    withJavadocJar()
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["java"])
            pom {
                name.set(provider { project.name })
                description.set(provider { project.description ?: project.name })
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
            // JReleaser reads from this directory; do NOT publish to a remote URL here.
            url = uri(rootProject.layout.buildDirectory.dir("staging-deploy"))
        }
    }
}

// Use base.archivesName (set per-module to e.g. "swiftkit-core") as the artifactId
// instead of the Gradle project name ("SwiftKitCore"). Done in afterEvaluate so the
// module's `base { archivesName = ... }` block has already run.
afterEvaluate {
    val archivesName = extensions.findByType<BasePluginExtension>()?.archivesName?.orNull
    if (!archivesName.isNullOrBlank()) {
        publishing.publications.withType<MavenPublication>().configureEach {
            artifactId = archivesName
        }
    }
}
