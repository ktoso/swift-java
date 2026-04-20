# Publishing swift-java Java libraries

This document explains how SwiftKit Java libraries (`swiftkit-core`,
`swiftkit-ffm`) are published to Maven Central and how downstream Java/Gradle
projects can consume them — including unreleased SNAPSHOT builds from `main`.

Publishing is driven by the [`com.vanniktech.maven.publish`](https://github.com/vanniktech/gradle-maven-publish-plugin)
plugin, applied via the [`build-logic.java-publishing-conventions`](BuildLogic/src/main/kotlin/build-logic.java-publishing-conventions.gradle.kts) convention.

## Coordinates

| Module | Maven coordinate | Notes |
|---|---|---|
| SwiftKitCore (Java) | `org.swift.swiftkit:swiftkit-core:<version>` | Pure Java, JNI bindings |
| SwiftKitFFM (Java) | `org.swift.swiftkit:swiftkit-ffm:<version>` | Pure Java, FFM bindings |
| SwiftKitCore native | `org.swift.swiftkit:swiftkit-core-native:<version>:<classifier>` | Per-platform dylibs |
| SwiftKitFFM native | `org.swift.swiftkit:swiftkit-ffm-native:<version>:<classifier>` | Per-platform dylibs |

The Java jars contain no native code. Each Java module needs the matching
native classifier jar at runtime, picked from this matrix:

| Classifier | Built on | Notes |
|---|---|---|
| `osx-aarch_64` | macOS 15 (arm64) | Apple Silicon |
| `ubuntu22.04-x86_64` | Ubuntu 22.04 (jammy) | Linux x86_64 |
| `ubuntu22.04-aarch_64` | Ubuntu 22.04 arm64 | |
| `ubuntu24.04-x86_64` | Ubuntu 24.04 (noble) | |
| `ubuntu24.04-aarch_64` | Ubuntu 24.04 arm64 | |
| `amazonlinux2-x86_64` | Amazon Linux 2 | Common on AWS |
| `amazonlinux2-aarch_64` | Amazon Linux 2 arm64 | Graviton |
| `linux-x86_64` | Swift static-linux SDK (musl) | Best-effort generic; statically linked Swift runtime |
| `linux-aarch_64` | Swift static-linux SDK (musl) | Best-effort generic, arm64 |

Swift's Linux runtime ABI is **not** stable across distros, so you generally
want a classifier matching your deployment target. The `linux-*` (static SDK)
variants try to bridge that gap but are best-effort.

## Versioning

The version is **derived from git tags** in [`build.gradle.kts`](./build.gradle.kts):

| Git state | Computed version |
|-----------|-----------------|
| HEAD is exactly at a tag matching `N.N.N` | that tag (release, e.g. `0.2.1`) |
| HEAD is past the latest tag | latest tag with patch + 1 + `-SNAPSHOT` (e.g. `0.2.1-SNAPSHOT` after `0.2.0`) |
| No tags at all | `0.0.1-SNAPSHOT` |

Print the resolved version with `./gradlew -q printVersion`. The publishing
convention enforces that snapshot publishes carry `-SNAPSHOT` and release
publishes do not.

## Where artifacts land

| Build kind | Repository |
|------------|-----------|
| SNAPSHOT   | https://central.sonatype.com/repository/maven-snapshots/ |
| RELEASE    | Maven Central |

## Consuming snapshots

### Gradle

The `osdetector` plugin auto-resolves the right classifier for the build host:

```kotlin
plugins {
    id("com.google.osdetector") version "1.7.3"
}

repositories {
    mavenCentral()
    maven("https://central.sonatype.com/repository/maven-snapshots/") {
        mavenContent { snapshotsOnly() }
    }
}

dependencies {
    implementation("org.swift.swiftkit:swiftkit-core:0.2.1-SNAPSHOT")
    runtimeOnly("org.swift.swiftkit:swiftkit-core-native:0.2.1-SNAPSHOT:${osdetector.classifier}")

    // For FFM bindings, similarly:
    // implementation("org.swift.swiftkit:swiftkit-ffm:0.2.1-SNAPSHOT")
    // runtimeOnly("org.swift.swiftkit:swiftkit-ffm-native:0.2.1-SNAPSHOT:${osdetector.classifier}")
}
```

Note: `osdetector.classifier` only distinguishes OS+arch, not Linux distro.
On Linux you may need to override it manually to pick the right `ubuntuXX.XX-*`
or `amazonlinux2-*` classifier matching your deployment target.

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

<repositories>
  <repository>
    <id>central-snapshots</id>
    <url>https://central.sonatype.com/repository/maven-snapshots/</url>
    <releases><enabled>false</enabled></releases>
    <snapshots><enabled>true</enabled></snapshots>
  </repository>
</repositories>

<dependencies>
  <dependency>
    <groupId>org.swift.swiftkit</groupId>
    <artifactId>swiftkit-core</artifactId>
    <version>0.2.1-SNAPSHOT</version>
  </dependency>
  <dependency>
    <groupId>org.swift.swiftkit</groupId>
    <artifactId>swiftkit-core-native</artifactId>
    <version>0.2.1-SNAPSHOT</version>
    <classifier>${os.detected.classifier}</classifier>
  </dependency>
</dependencies>
```

## CI workflows

Two GitHub Actions workflows handle publishing:

| Workflow | Trigger | What it does |
|----------|---------|--------------|
| [`.github/workflows/snapshot-publish.yml`](.github/workflows/snapshot-publish.yml) | Push to `main` and manual `workflow_dispatch` | One Java publish job + matrix of native publish jobs (one per platform classifier). Snapshots route to the Sonatype snapshots repo. |
| [`.github/workflows/release-publish.yml`](.github/workflows/release-publish.yml) | Push of a `N.N.N` tag, or manual `workflow_dispatch` | Same shape as snapshot, plus tag/version match validation. Releases stage to a Central Portal deployment for manual finalization. |

Each workflow has three job groups:

1. **`publish-java`** — runs `:SwiftKitCore:publishToMavenCentral :SwiftKitFFM:publishToMavenCentral`. Single Linux container job. Publishes the classifier-less Java jars.
2. **`publish-natives-linux`** — 8-entry matrix; each entry runs `:SwiftKitCoreNative:publishToMavenCentral :SwiftKitFFMNative:publishToMavenCentral` with `-PnativeClassifier=<classifier>` (and `-PnativeBuildSdk=<sdk>` for the static SDK variants).
3. **`publish-natives-macos`** — single macOS arm64 job, mirrors the Linux matrix entries.

All native jobs depend on `publish-java` succeeding. Each native job uploads only its own classifier jar to the same coordinates as the others — Central Portal accepts multiple uploads to the same `groupId:artifactId:version` as long as classifiers differ.

## Required GitHub Actions secrets

Configure these in the repository settings (`Settings → Secrets and variables → Actions`):

| Secret | Description |
|--------|-------------|
| `SONATYPE_USER` | Sonatype Central Portal user token name. Generate at https://central.sonatype.com/account |
| `SONATYPE_TOKEN` | Sonatype Central Portal user token value (paired with the user token name) |
| `ORG_GRADLE_PROJECT_SIGNINGKEY` | Armored PGP private key used to sign published artifacts. Export with `gpg --armor --export-secret-key <KEY_ID>` |
| `ORG_GRADLE_PROJECT_SIGNINGPASSWORD` | Passphrase for the PGP key |

The workflows map these to the property names vanniktech expects
(`mavenCentralUsername`, `mavenCentralPassword`, `signingInMemoryKey`,
`signingInMemoryKeyPassword`) via `ORG_GRADLE_PROJECT_*` env vars.

> **One-time setup:** the `org.swift.swiftkit` namespace must be claimed on the
> Sonatype Central Portal before the first publish. See
> https://central.sonatype.org/register/central-portal/ for the namespace
> verification flow.

## Local verification

Publish to your local Maven repository (no signing, no network). Native artifacts
will be tagged with your host's `osdetector` classifier:

```bash
./gradlew \
    :SwiftKitCore:publishToMavenLocal \
    :SwiftKitFFM:publishToMavenLocal \
    :SwiftKitCoreNative:publishToMavenLocal \
    :SwiftKitFFMNative:publishToMavenLocal
```

Artifacts land under `~/.m2/repository/org/swift/swiftkit/`. The native jars
will appear with your host classifier, e.g. `swiftkit-core-native-VERSION-osx-aarch_64.jar`.

Override the classifier explicitly with `-PnativeClassifier=<classifier>`. To
exercise the static-linux SDK build, also pass `-PnativeBuildSdk=<sdk-id>`:

```bash
./gradlew :SwiftKitCoreNative:publishToMavenLocal \
    -PnativeClassifier=linux-x86_64 \
    -PnativeBuildSdk=x86_64-swift-linux-musl
```

To inspect the resolved version:

```bash
./gradlew -q printVersion
```

## Cutting a release

Use [`scripts/release.sh`](./scripts/release.sh). It will:

1. Pin `swift-java-jni-core` to its latest release tag in `Package.swift`.
2. Build both Swift and Gradle to verify.
3. Push a `release/<version>` branch for review.
4. After you tag the merge commit (`git tag -s <version> -m <version>`) and push
   the tag, `build.gradle.kts` derives the release version from that tag, and
   the `release-publish.yml` workflow runs automatically.
5. After the workflow finishes, finalize the deployment at
   https://central.sonatype.com/publishing/deployments.
6. Re-run `./scripts/release.sh --next` to re-point `swift-java-jni-core` back
   to `main`. No `gradle.properties` bump is needed — the next commit on `main`
   automatically resolves to `<next-patch>-SNAPSHOT`.
