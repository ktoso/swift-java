# Publishing swift-java Java libraries

This document explains how SwiftKit's Java libraries (`swiftkit-core`,
`swiftkit-ffm`) and their per-platform native dylibs are published to Maven
Central, and how downstream Java/Gradle projects consume them — including
unreleased SNAPSHOT builds from `main`.

Publishing is driven by [JReleaser](https://jreleaser.org/) — the approach
[Sonatype documents](https://central.sonatype.org/publish/publish-portal-gradle/)
for the Central Portal — applied at the root of the Gradle build. Each module
applies the appropriate convention plugin under
[`BuildLogic/src/main/kotlin/`](BuildLogic/src/main/kotlin/):
- [`build-logic.java-publishing-conventions`](BuildLogic/src/main/kotlin/build-logic.java-publishing-conventions.gradle.kts)
  for the Java jars
- [`build-logic.native-publishing-conventions`](BuildLogic/src/main/kotlin/build-logic.native-publishing-conventions.gradle.kts)
  for the per-platform classifier jars

## Coordinates

| Module | Maven coordinate | Notes |
|---|---|---|
| SwiftKitCore (Java) | `org.swift.swiftjava:swiftkit-core:<version>` | Pure Java, JNI bindings |
| SwiftKitFFM (Java) | `org.swift.swiftjava:swiftkit-ffm:<version>` | Pure Java, FFM bindings (JDK 22+) |
| SwiftKitCore native | `org.swift.swiftjava:swiftkit-core-native:<version>:<classifier>` | Per-platform dylibs |
| SwiftKitFFM native | `org.swift.swiftjava:swiftkit-ffm-native:<version>:<classifier>` | Per-platform dylibs |

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

The dylibs are bundled at `META-INF/native/` inside the classifier jar, where
`SwiftLibraries.loadResourceLibrary` looks them up at runtime via
`getResourceAsStream("/META-INF/native/libFoo.dylib")`.

## Versioning

The version is **derived from git tags** in [`build.gradle.kts`](./build.gradle.kts):

| Git state | Computed version |
|-----------|-----------------|
| HEAD is exactly at a tag matching `N.N.N` | that tag (release, e.g. `0.2.1`) |
| HEAD is past the latest tag | latest tag with patch + 1 + `-SNAPSHOT` (e.g. `0.2.1-SNAPSHOT` after `0.2.0`) |
| No tags at all | `0.0.1-SNAPSHOT` |

Print the resolved version with `./gradlew -q printVersion`. The publish
workflows enforce that snapshot publishes carry `-SNAPSHOT` and release
publishes do not (and that the tag matches the version).

## Where artifacts land

| Build kind | Repository |
|------------|-----------|
| SNAPSHOT   | https://central.sonatype.com/repository/maven-snapshots/ |
| RELEASE    | Maven Central (via Sonatype Central Portal staging) |

JReleaser routes by version suffix:
- non-SNAPSHOT versions → `mavenCentral.release-deploy` deployer → Portal Publisher API
- SNAPSHOT versions → `nexus2.snapshot-deploy` deployer → Central Portal snapshot repo

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
    implementation("org.swift.swiftjava:swiftkit-core:0.2.1-SNAPSHOT")
    runtimeOnly("org.swift.swiftjava:swiftkit-core-native:0.2.1-SNAPSHOT:${osdetector.classifier}")

    // For FFM bindings on JDK 22+:
    // implementation("org.swift.swiftjava:swiftkit-ffm:0.2.1-SNAPSHOT")
    // runtimeOnly("org.swift.swiftjava:swiftkit-ffm-native:0.2.1-SNAPSHOT:${osdetector.classifier}")
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
    <groupId>org.swift.swiftjava</groupId>
    <artifactId>swiftkit-core</artifactId>
    <version>0.2.1-SNAPSHOT</version>
  </dependency>
  <dependency>
    <groupId>org.swift.swiftjava</groupId>
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
| [`.github/workflows/snapshot-publish.yml`](.github/workflows/snapshot-publish.yml) | Push to `main`; manual `workflow_dispatch` | One Java publish job + matrix of native publish jobs (one per platform classifier). Snapshots route to the Sonatype snapshots repo. |
| [`.github/workflows/release-publish.yml`](.github/workflows/release-publish.yml) | Push of a `N.N.N` tag; manual `workflow_dispatch` with `ref` input | Same shape as snapshot, plus tag/version match validation. Releases stage to Central Portal deployments for manual finalization. |

Each workflow has three job groups:

1. **`publish-java`** — single Linux container job. Runs `:SwiftKitCore:publish :SwiftKitFFM:publish` to stage to `build/staging-deploy/`, then `./gradlew jreleaserDeploy`. Publishes the classifier-less Java jars.
2. **`publish-natives-linux`** — 8-entry matrix; each entry runs `:SwiftKitCoreNative:publish :SwiftKitFFMNative:publish` with `-PnativeClassifier=<classifier>` (and `-PnativeBuildSdk=<sdk>` for the static-SDK variants), then `./gradlew jreleaserDeploy`.
3. **`publish-natives-macos`** — single macOS arm64 job, mirrors the Linux pattern with classifier `osx-aarch_64`.

All native jobs depend on `publish-java` succeeding. **Each matrix job creates its own Sonatype Central Portal deployment** — for releases this means ~10 deployments to click "Publish" on per release. Snapshot uploads are silent (no clicks needed).

## Required GitHub Actions secrets

Configure in repo Settings → Secrets and variables → Actions. The publish workflows use these env-var names verbatim (JReleaser reads `JRELEASER_*` env vars directly).

| Secret | Description |
|--------|-------------|
| `JRELEASER_MAVENCENTRAL_USERNAME` | Sonatype Central Portal user-token name. Generate at https://central.sonatype.com/account |
| `JRELEASER_MAVENCENTRAL_PASSWORD` | Sonatype Central Portal user-token value (paired with the username) |
| `JRELEASER_NEXUS2_USERNAME` | Snapshot upload credentials. Try the same Portal user-token first; if 401, file an OSSRH JIRA ticket linked to the verified namespace. |
| `JRELEASER_NEXUS2_PASSWORD` | Snapshot upload password (matching the username above) |
| `JRELEASER_GPG_PUBLIC_KEY` | Armored PGP public key. Export with `gpg --armor --export <KEY_ID>` |
| `JRELEASER_GPG_SECRET_KEY` | Armored PGP private key. Export with `gpg --armor --export-secret-key <KEY_ID>` |
| `JRELEASER_GPG_PASSPHRASE` | Passphrase for the PGP key |

The workflows also pass `JRELEASER_GITHUB_TOKEN=${{ secrets.GITHUB_TOKEN }}` to satisfy JReleaser's required `release.github.token` field. Our config sets `release.github.skipRelease = true; skipTag = true`, so the token is never used to mutate GitHub state — but JReleaser validates that *some* token is present.

> **One-time setup:** the `org.swift.swiftjava` namespace must be claimed on the
> Sonatype Central Portal before the first publish, including DNS TXT verification
> on `swift.org`. See https://central.sonatype.org/register/central-portal/ for
> the namespace verification flow.

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
    -PnativeClassifier=linux-x86_64 \
    -PnativeBuildSdk=x86_64-swift-linux-musl
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

## Cutting a release

Use [`scripts/release.sh`](./scripts/release.sh). The flow is:

1. Pin `swift-java-jni-core` to its latest release tag in `Package.swift`.
2. Verify Swift and Gradle builds succeed.
3. Push a `release/<version>` branch for review.
4. After you tag the merge commit (`git tag -s <version> -m <version>`) and push
   the tag, `build.gradle.kts` derives the release version from that tag, and
   the [`release-publish.yml`](.github/workflows/release-publish.yml) workflow
   runs automatically.
5. After the workflow finishes, finalize each staged deployment at
   https://central.sonatype.com/publishing/deployments. **Each native classifier
   creates its own deployment** (matrix design); review and click Publish on each.
6. Re-run `./scripts/release.sh --next` to re-point `swift-java-jni-core` back
   to `main`. No `gradle.properties` bump is needed — the next commit on `main`
   automatically resolves to `<next-patch>-SNAPSHOT`.

> Once any deployment is **Published**, that exact `<groupId>:<artifactId>:<version>:<classifier>` is permanent. Mistakes get fixed by tagging `0.X.Y+1` next, never by republishing.
