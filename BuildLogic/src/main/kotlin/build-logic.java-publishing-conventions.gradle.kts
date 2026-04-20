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

// Publishing convention for swift-java Java libraries
//
// Uses the com.vanniktech.maven.publish plugin which:
//   - Publishes to the Sonatype Central Portal (snapshots and releases)
//   - Generates sources + javadoc jars
//   - Reads credentials from `mavenCentralUsername` / `mavenCentralPassword` properties
//   - Reads PGP signing key material from `signingInMemoryKey*` properties
//
// Snapshots (-SNAPSHOT version) publish to:
//   https://central.sonatype.com/repository/maven-snapshots/
// Releases (non-SNAPSHOT version) stage in the Central Portal for manual finalization at:
//   https://central.sonatype.com/publishing/deployments

import com.vanniktech.maven.publish.JavaLibrary
import com.vanniktech.maven.publish.JavadocJar
import com.vanniktech.maven.publish.SourcesJar

plugins {
    id("com.vanniktech.maven.publish")
}

mavenPublishing {
    publishToMavenCentral(automaticRelease = false)
    signAllPublications()

    configure(
        JavaLibrary(
            javadocJar = JavadocJar.Javadoc(),
            sourcesJar = SourcesJar.Sources(),
        )
    )

    val scmHost: String = providers.gradleProperty("scmHost").orNull ?: ""
    val scmPath: String = providers.gradleProperty("scmPath").orNull ?: ""

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

// Use `base.archivesName` (set per-module to e.g. "swiftkit-core") as the artifactId
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
