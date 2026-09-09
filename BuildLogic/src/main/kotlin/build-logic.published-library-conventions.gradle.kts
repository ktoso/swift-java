//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2026 Apple Inc. and the Swift.org project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift.org project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import org.gradle.api.plugins.BasePluginExtension
import org.gradle.api.tasks.SourceSetContainer
import com.google.gradle.osdetector.OsDetector

plugins {
    `maven-publish`
    signing
}

// Applied the legacy way (not via the `plugins {}` block above) because this file is
// itself compiled into a plugin reused by other builds, and the osdetector plugin is
// only present on BuildLogic's own classpath (see BuildLogic/build.gradle.kts), not
// published with a plugin marker resolvable by id+version from here
apply(plugin = "com.google.osdetector")
val osDetector = extensions.getByType<OsDetector>()

group = "org.swift.swiftjava"

// ==== -----------------------------------------------------------------------
// MARK: Native-library classifier opt-in

// Off by default: today's published jars are pure-Java. A future module that
// bundles native (Swift) binaries can opt in with `swiftJava { publishesNativeLibraries = true }`
// to get an OS/arch classifier on its jar
abstract class SwiftJavaPublishingExtension {
    abstract val publishesNativeLibraries: Property<Boolean>
}

val swiftJava = extensions.create<SwiftJavaPublishingExtension>("swiftJava")
swiftJava.publishesNativeLibraries.convention(false)

afterEvaluate {
    if (swiftJava.publishesNativeLibraries.get()) {
        tasks.named<Jar>("jar") {
            archiveClassifier = osDetector.classifier
        }
    }
}

// ==== -----------------------------------------------------------------------
// MARK: Version scheme guard

// CI always passes an explicit `-PswiftkitVersion`, so this is a belt-and-suspenders
// check that catches a misconfigured workflow before it publishes the wrong thing
val isReleaseBuild = project.hasProperty("releaseBuild")

afterEvaluate {
    val endsWithSnapshot = version.toString().uppercase().endsWith("-SNAPSHOT")
    if (isReleaseBuild) {
        check(!endsWithSnapshot) {
            "Project version for a release build must not contain a '-SNAPSHOT' suffix (was: $version)"
        }
    } else {
        check(endsWithSnapshot) {
            "Project version for a non-release build must contain a '-SNAPSHOT' suffix (was: $version)"
        }
    }
}

// ==== -----------------------------------------------------------------------
// MARK: Sources / javadoc jars

// Captured here (project scope) rather than inside the task configuration blocks
// below, because an unqualified `extensions` reference inside a task's own
// configuration lambda resolves to that task's own (near-empty) extension
// container, not the project's
val mainSourceSet = extensions.getByType<SourceSetContainer>()["main"]

val sourcesJar by tasks.registering(Jar::class) {
    archiveClassifier = "sources"
    from(mainSourceSet.allSource)
}

val javadocJar by tasks.registering(Jar::class) {
    archiveClassifier = "javadoc"
    from(tasks.named("javadoc"))
}

tasks.withType<Javadoc>().configureEach {
    // SwiftKitFFM uses java.lang.foreign preview APIs, so its javadoc task needs the
    // equivalent of javac's --release/--enable-preview flags. Gradle's
    // addStringOption/addBooleanOption always prepend one '-' to the given option name,
    // so passing a name that already starts with '-' produces the required '--' flag
    val docOptions = options as StandardJavadocDocletOptions
    docOptions.addStringOption("-release", "25")
    docOptions.addBooleanOption("-enable-preview", true)
}

// ==== -----------------------------------------------------------------------
// MARK: Publication + POM metadata

// Deferred to afterEvaluate: each consuming module only sets `base.archivesName`
// later in its own build script, after this convention plugin has already been
// applied, and MavenPublication does not pick up base.archivesName as its default
// artifactId reliably, so it is read and assigned explicitly here instead
afterEvaluate {
    val archivesName = the<BasePluginExtension>().archivesName.get()

    publishing {
        publications {
            create<MavenPublication>("maven") {
                artifactId = archivesName
                from(components["java"])
                artifact(sourcesJar)
                artifact(javadocJar)

                pom {
                    name = project.name
                    description = "Swift/Java interoperability tools and libraries"
                    url = "https://github.com/swiftlang/swift-java"
                    licenses {
                        license {
                            name = "Apache License, Version 2.0"
                            url = "https://www.apache.org/licenses/LICENSE-2.0.txt"
                        }
                    }
                    developers {
                        developer {
                            id = "swift-server"
                            name = "Swift.org"
                            url = "https://swift.org"
                        }
                    }
                    scm {
                        connection = "scm:git:https://github.com/swiftlang/swift-java.git"
                        developerConnection = "scm:git:ssh://git@github.com/swiftlang/swift-java.git"
                        url = "https://github.com/swiftlang/swift-java"
                    }
                }
            }
        }

        repositories {
            maven {
                name = "sonatype"
                url = uri(
                    if (isReleaseBuild)
                        "https://ossrh-staging-api.central.sonatype.com/service/local/staging/deploy/maven2/"
                    else
                        "https://central.sonatype.com/repository/maven-snapshots/"
                )
                credentials {
                    username = System.getenv("SONATYPE_USER")
                    password = System.getenv("SONATYPE_TOKEN")
                }
            }
        }
    }

    // ==== -------------------------------------------------------------------
    // MARK: Signing (conditional, in-memory PGP keys)

    // Local builds without these properties simply skip signing
    val signingKey = findProperty("signingKey") as String?
    val signingPassword = findProperty("signingPassword") as String?
    if (!signingKey.isNullOrBlank() && !signingPassword.isNullOrBlank()) {
        signing {
            useInMemoryPgpKeys(signingKey, signingPassword)
            sign(publishing.publications["maven"])
        }
    }
}
