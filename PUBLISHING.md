# Publishing swift-java Java libraries

This document explains how SwiftKit's Java libraries (`swiftkit-core`,
`swiftkit-ffm`) and their per-platform native dylibs are published to Maven
Central, and how downstream Java/Gradle projects consume them — including
unreleased SNAPSHOT builds from `main`.

For maintainer setup (GPG key generation, GitHub Secrets configuration), the
CI workflows that perform the publishing, and the recurring release flow, see
[`RELEASING.md`](./RELEASING.md).

Publishing is driven by [JReleaser](https://jreleaser.org/) — the approach
[Sonatype documents](https://central.sonatype.org/publish/publish-portal-gradle/)
for the Central Portal — applied at the root of the Gradle build. Each module
applies the appropriate convention plugin under
[`BuildLogic/src/main/kotlin/`](BuildLogic/src/main/kotlin/):
- [`build-logic.java-publishing-conventions`](BuildLogic/src/main/kotlin/build-logic.java-publishing-conventions.gradle.kts)
  for the Java jars
- [`build-logic.native-swift-publishing-conventions`](BuildLogic/src/main/kotlin/build-logic.native-swift-publishing-conventions.gradle.kts)
  for the per-platform classifier jars

## Coordinates

| Module              | Maven coordinate                                                   | Notes                              |
| ------------------- | ------------------------------------------------------------------ | ---------------------------------- |
| SwiftKitCore (Java) | `org.swift.swiftjava:swiftkit-core:<version>`                      | Pure Java, JNI bindings            |
| SwiftKitFFM (Java)  | `org.swift.swiftjava:swiftkit-ffm:<version>`                       | Pure Java, FFM bindings (JDK 25+)  |
| SwiftKitCore native | `org.swift.swiftjava:swiftkit-core-native:<version>:<classifier>`  | Per-platform dylibs                |
| SwiftKitFFM native  | `org.swift.swiftjava:swiftkit-ffm-native:<version>:<classifier>`   | Per-platform dylibs                |

The Java jars contain no native code. Each Java module needs the matching
native classifier jar at runtime, picked from this matrix (Linux classifiers
encode the Swift toolchain version because Swift's Linux runtime ABI is not
stable across toolchain versions; macOS does not, since Apple's Swift ABI is
stable):

| Classifier                            | Built on                       | Notes                                                |
| ------------------------------------- | ------------------------------ | ---------------------------------------------------- |
| `osx-aarch_64`                        | macOS 15 (arm64)               | Apple Silicon                                        |
| `ubuntu22.04-swift_<X.Y>-x86_64`      | Ubuntu 22.04 (jammy)           | Linux x86_64                                         |
| `ubuntu22.04-swift_<X.Y>-aarch_64`    | Ubuntu 22.04 arm64             |                                                      |
| `ubuntu24.04-swift_<X.Y>-x86_64`      | Ubuntu 24.04 (noble)           |                                                      |
| `ubuntu24.04-swift_<X.Y>-aarch_64`    | Ubuntu 24.04 arm64             |                                                      |
| `amazonlinux2-swift_<X.Y>-x86_64`     | Amazon Linux 2                 | Common on AWS                                        |
| `amazonlinux2-swift_<X.Y>-aarch_64`   | Amazon Linux 2 arm64           | Graviton                                             |
| `linux-swift_<X.Y>-x86_64`            | Swift static-linux SDK (musl)  | Best-effort generic; statically linked Swift runtime |
| `linux-swift_<X.Y>-aarch_64`          | Swift static-linux SDK (musl)  | Best-effort generic, arm64                           |

`<X.Y>` is the Swift toolchain version that produced the dylibs (e.g.
`swift_6.3`). Pick a classifier matching your deployment target's distro and
Swift runtime; the `linux-*` (static SDK) variants are best-effort generic.

The dylibs are bundled at `META-INF/native/` inside the classifier jar, where
`SwiftLibraries.loadResourceLibrary` looks them up at runtime via
`getResourceAsStream("/META-INF/native/libFoo.dylib")`. Each native jar's
`META-INF/MANIFEST.MF` includes a `Swift-Version` attribute identifying the
toolchain that produced it.

## Versioning

The version is **derived from git tags** in [`build.gradle.kts`](./build.gradle.kts):

| Git state                                  | Computed version                                                                       |
| ------------------------------------------ | -------------------------------------------------------------------------------------- |
| HEAD is exactly at a tag matching `N.N.N`  | that tag (release, e.g. `0.2.1`)                                                       |
| HEAD is past the latest tag                | latest tag with patch + 1 + `-SNAPSHOT` (e.g. `0.2.1-SNAPSHOT` after `0.2.0`)          |
| No tags at all                             | `0.0.1-SNAPSHOT`                                                                       |

Print the resolved version with `./gradlew -q printVersion`.

## Target repositories

| Build kind | Repository                                                |
| ---------- | --------------------------------------------------------- |
| RELEASE    | Maven Central (via Sonatype Central Portal staging)       |
| SNAPSHOT   | https://central.sonatype.com/repository/maven-snapshots/  |

JReleaser routes by version suffix:
- non-SNAPSHOT versions → `mavenCentral.release-deploy` deployer → Portal Publisher API
- SNAPSHOT versions → `nexus2.snapshot-deploy` deployer → Central Portal snapshot repo

## Consuming swift-java

### Gradle

The `osdetector` plugin auto-resolves the OS+arch portion of the classifier
for the build host; you must still supply the Swift version segment yourself
on Linux (osdetector knows nothing about Swift). For example, on Linux, target
Swift 6.3:

```kotlin
plugins {
    id("com.google.osdetector") version "1.7.3"
}

repositories {
    mavenCentral()
}

dependencies {
    implementation("org.swift.swiftjava:swiftkit-core:0.2.1")
    runtimeOnly("org.swift.swiftjava:swiftkit-core-native:0.2.1:linux-swift_6.3-x86_64")

    // FFM bindings (JDK 25+):
    implementation("org.swift.swiftjava:swiftkit-ffm:0.2.1")
    runtimeOnly("org.swift.swiftjava:swiftkit-ffm-native:0.2.1:linux-swift_6.3-x86_64")
}
```

On macOS, `osdetector.classifier` resolves to `osx-aarch_64` directly:

```kotlin
runtimeOnly("org.swift.swiftjava:swiftkit-core-native:0.2.1:${osdetector.classifier}")
```

#### Using snapshots

If you want to use unreleased SNAPSHOT builds from `main`, add the snapshots
repository:

```kotlin
repositories {
    mavenCentral()
    maven("https://central.sonatype.com/repository/maven-snapshots/") {
        mavenContent { snapshotsOnly() }
    }
}

dependencies {
    implementation("org.swift.swiftjava:swiftkit-core:0.2.1-SNAPSHOT")
    runtimeOnly("org.swift.swiftjava:swiftkit-core-native:0.2.1-SNAPSHOT:linux-swift_6.3-x86_64")
}
```

### Maven

```xml
<build>
  <extensions>
    <extension>
      <groupId>kr.motd.maven</groupId>
      <artifactId>os-maven-plugin</artifactId>
      <version>1.7.1</version>
    </extension>
  </extensions>
</build>

<dependencies>
  <dependency>
    <groupId>org.swift.swiftjava</groupId>
    <artifactId>swiftkit-core</artifactId>
    <version>0.2.1</version>
  </dependency>
  <dependency>
    <groupId>org.swift.swiftjava</groupId>
    <artifactId>swiftkit-core-native</artifactId>
    <version>0.2.1</version>
    <classifier>linux-swift_6.3-x86_64</classifier>
  </dependency>
</dependencies>
```

#### Using snapshots

When you want to use snapshots, add the snapshots repository:

```xml
<repositories>
  <repository>
    <id>central-snapshots</id>
    <url>https://central.sonatype.com/repository/maven-snapshots/</url>
    <releases><enabled>false</enabled></releases>
    <snapshots><enabled>true</enabled></snapshots>
  </repository>
</repositories>
```

## Local verification

Publish to your local Maven repository (no signing, no network). Native
artifacts will be tagged with your host's `osdetector` classifier:

```bash
./gradlew \
    :SwiftKitCore:publishToMavenLocal \
    :SwiftKitFFM:publishToMavenLocal \
    :SwiftKitCoreNative:publishToMavenLocal \
    :SwiftKitFFMNative:publishToMavenLocal
```

Artifacts land under `~/.m2/repository/org/swift/swiftjava/`. The native jars
will appear with your host classifier, e.g.
`swiftkit-core-native-VERSION-osx-aarch_64.jar`.

To stage everything to the local `build/staging-deploy/` directory that JReleaser
consumes (no upload, no signing):

```bash
./gradlew stageForJReleaser
find build/staging-deploy -type f
```

Override the classifier explicitly with `-PnativeClassifier=<classifier>`. To
exercise the static-linux SDK build, also pass `-PnativeBuildSdk=<sdk-id>`:

```bash
./gradlew :SwiftKitCoreNative:publishToMavenLocal \
    -PnativeClassifier=linux-swift_6.3-x86_64 \
    -PnativeBuildSdk=x86_64-swift-linux-musl \
    -PswiftVersion=6.3
```

Inspect the resolved version:

```bash
./gradlew -q printVersion
```

Validate the JReleaser config (requires dummy creds locally):

```bash
JRELEASER_GPG_PUBLIC_KEY=dummy JRELEASER_GPG_SECRET_KEY=dummy \
JRELEASER_GPG_PASSPHRASE=dummy \
JRELEASER_NEXUS2_USERNAME=dummy JRELEASER_NEXUS2_PASSWORD=dummy \
JRELEASER_MAVENCENTRAL_USERNAME=dummy JRELEASER_MAVENCENTRAL_PASSWORD=dummy \
JRELEASER_GITHUB_TOKEN=dummy \
./gradlew jreleaserConfig
```

Test signing locally with a real GPG key (no upload):

```bash
export JRELEASER_GPG_PUBLIC_KEY="$(gpg --armor --export <KEYID>)"
export JRELEASER_GPG_SECRET_KEY="$(gpg --armor --export-secret-keys <KEYID>)"
export JRELEASER_GPG_PASSPHRASE="<your-passphrase>"
./gradlew stageForJReleaser
./gradlew jreleaserSign
ls build/jreleaser/sign/
```
