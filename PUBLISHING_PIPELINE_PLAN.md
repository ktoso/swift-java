# swift-java Maven Central publishing pipeline

## Context

swift-java currently has **no publishing pipeline**. `SwiftKitCore` and `SwiftKitFFM` apply
`maven-publish` but define no signing, no remote repository, and no POM metadata, so nothing is
publishable to Maven Central. There is only a PR CI workflow (`.github/workflows/pull_request.yml`);
no snapshot or release automation exists. `scripts/release.sh` stops after creating a release branch
and merely prints a manual "create the tag" step.

Goal: a publishing pipeline modeled on ServiceTalk's (stock Gradle `maven-publish` + `signing`,
in-memory GPG keys, Sonatype **Central Portal** OSSRH staging API, secrets from GitHub Actions),
adapted to swift-java's composite Gradle build. Requirements from the user, with decisions made:

- **Group `org.swift.swiftjava`** for all published artifacts (was `org.swift.swiftkit`; this is a
  deliberate breaking coordinate change). Artifacts stay `swiftkit-core` / `swiftkit-ffm`.
- **OS classifier only when a jar bundles native binaries** (dylib/so/dll). Implemented as a reusable
  convention that is **off by default**; the currently shipped jars are pure-Java so they publish
  classifier-less. No native jars are shipped yet, and the CI runner matrix is not expanded.
- **Snapshot publish on every merge to `main`.**
- **Release publish on a pushed tag that must be a GPG-signed annotated tag**; the release is
  **staged** to the Central Portal and finished manually in the Central UI (a click), matching
  ServiceTalk. Signature is verified in CI with `git verify-tag` against a **committed
  allowed-signers keyring**.
- **All credentials come from GitHub Actions secrets.**

## Reference design (ServiceTalk, for parity)

- `~/code/servicetalk/.github/workflows/ci-snapshot.yml` (branch push, guards `-SNAPSHOT`) and
  `ci-release.yml` (tag push, guards non-`-SNAPSHOT`, curl "manual close" of the staging repo).
- Publishing/signing live in a convention plugin
  (`servicetalk-gradle-plugin-internal/.../ServiceTalkLibraryPlugin.groovy`): in-memory PGP keys,
  conditional signing, single `sonatype` maven repo whose URL flips on `isReleaseBuild`.
- Secrets: `ORG_GRADLE_PROJECT_SIGNINGKEY`, `ORG_GRADLE_PROJECT_SIGNINGPASSWORD`, `SONATYPE_USER`,
  `SONATYPE_TOKEN`. ServiceTalk does **not** verify signed tags - we add that.

## Changes

### 1. New Gradle convention plugin: publishing + signing

Add `BuildLogic/src/main/kotlin/build-logic.published-library-conventions.gradle.kts` (sits alongside
the existing `build-logic.java-*-conventions.gradle.kts`). It centralizes everything ServiceTalk keeps
in its library plugin. Responsibilities:

- Apply `maven-publish`, `signing`, and `com.google.osdetector` (version `1.7.3`, already used by the
  sample lib).
- Set `group = "org.swift.swiftjava"`.
- Version scheme guard mirroring ServiceTalk's `enforceProjectVersionScheme`: read a `releaseBuild`
  project property into `isReleaseBuild`; fail a release build whose version ends in `-SNAPSHOT`, and
  fail a non-release build whose version does **not** end in `-SNAPSHOT` (CI passes explicit versions
  via `-PswiftkitVersion`, so this is a belt-and-suspenders check).
- Create `sourcesJar` and `javadocJar` tasks (classifiers `sources` / `javadoc`) - Central requires
  both. (Caveat: SwiftKitFFM uses preview APIs; its javadoc task needs `--release 25 --enable-preview`
  or equivalent - configure `(options as StandardJavadocDocletOptions)` accordingly.)
- Define the `maven` publication: `from(components["java"])` + the sources/javadoc jars, and a full
  POM (name, description, `url=https://github.com/swiftlang/swift-java`, Apache-2.0 license,
  `scm` -> swiftlang/swift-java, `developers` = Swift.org authors). Central rejects POMs missing these.
- **OS-classifier convention (opt-in, off by default):** register an extension flag, e.g.
  `swiftJava { publishesNativeLibraries = false }`. When `true`, set
  `tasks.jar { archiveClassifier = osdetector.classifier }` (the exact recipe from
  `Samples/SwiftAndJavaJarFFMSampleLib/build.gradle.kts:88-90`). All current modules leave it `false`,
  so they publish classifier-less pure-Java jars. Documented so a future native module flips one flag.
- Signing (conditional, in-memory PGP), copied from ServiceTalk:
  ```kotlin
  val signingKey = findProperty("signingKey") as String?
  val signingPassword = findProperty("signingPassword") as String?
  if (!signingKey.isNullOrBlank() && !signingPassword.isNullOrBlank()) {
      signing {
          useInMemoryPgpKeys(signingKey, signingPassword)
          sign(publishing.publications["maven"])
      }
  }
  ```
  Local builds without the secrets skip signing.
- Sonatype Central Portal repository, URL switched on `isReleaseBuild`:
  ```kotlin
  publishing.repositories.maven {
      name = "sonatype"
      url = uri(if (isReleaseBuild)
          "https://ossrh-staging-api.central.sonatype.com/service/local/staging/deploy/maven2/"
      else
          "https://central.sonatype.com/repository/maven-snapshots/")
      credentials {
          username = System.getenv("SONATYPE_USER")
          password = System.getenv("SONATYPE_TOKEN")
      }
  }
  ```

### 2. Apply the convention to the shipped modules

- `SwiftKitCore/build.gradle.kts`: replace the inline `group = "org.swift.swiftkit"` + `publishing {}`
  block (lines 23, 36-44) with `id("build-logic.published-library-conventions")` and keep
  `base.archivesName = "swiftkit-core"` (drives artifactId). Version stays `resolveSwiftKitVersion()`.
- `SwiftKitFFM/build.gradle.kts`: same treatment (lines 22, 35-43), `archivesName = "swiftkit-ffm"`.
- Leave `Samples/SwiftAndJavaJarFFMSampleLib/build.gradle.kts` as-is (publishes to `mavenLocal` only;
  it already demonstrates the native-classifier recipe the convention now generalizes).

### 3. Version derivation for snapshots

`resolveSwiftKitVersion()` (`BuildLogic/.../utils/gitVersion.kt`) already honors `-PswiftkitVersion`
first. CI passes an explicit version so off-tag `git describe` (e.g. `0.6.0-3-gSHA`, not a valid Maven
version) is never used:

- Add `scripts/next-snapshot-version.sh`: reads `git describe --tags --abbrev=0` (e.g. `0.6.0`),
  bumps the patch, prints `0.6.1-SNAPSHOT`. Used by the snapshot workflow.
- Release workflow passes the tag name verbatim as the version.

### 4. Committed tag-signer keyring

Add `.github/release-signers.asc` containing the ASCII-armored **public** keys of maintainers allowed
to sign release tags. CI imports it and runs `git verify-tag`. (Distinct from the artifact-signing
*private* key, which stays a secret.) Document in the repo how to add a maintainer key.

### 5. GitHub Actions workflows

**`.github/workflows/publish-snapshot.yml`** - snapshot on merge to main:
- Trigger: `push` to `main`, ignoring doc/script-only paths and ignoring tags (mirror ci-snapshot.yml).
- Runner `ubuntu-latest`; `actions/checkout@v5` with `fetch-depth: 0` and `fetch-tags: true` (needed
  for `git describe`); `actions/setup-java@v5` JDK 25 (FFM needs 22+), gradle cache.
- `VERSION=$(scripts/next-snapshot-version.sh)`; assert it ends with `-SNAPSHOT`.
- `./gradlew :SwiftKitCore:publishAllPublicationsToSonatypeRepository :SwiftKitFFM:publishAllPublicationsToSonatypeRepository -PswiftkitVersion=$VERSION`
  (no `-PreleaseBuild` -> snapshot URL).
- `env:` maps the four secrets, using Gradle's `ORG_GRADLE_PROJECT_` convention so they arrive as the
  `signingKey`/`signingPassword` project properties:
  ```yaml
  ORG_GRADLE_PROJECT_signingKey: ${{ secrets.ORG_GRADLE_PROJECT_SIGNINGKEY }}
  ORG_GRADLE_PROJECT_signingPassword: ${{ secrets.ORG_GRADLE_PROJECT_SIGNINGPASSWORD }}
  SONATYPE_USER: ${{ secrets.SONATYPE_USER }}
  SONATYPE_TOKEN: ${{ secrets.SONATYPE_TOKEN }}
  ```

**`.github/workflows/publish-release.yml`** - release on signed tag:
- Trigger: `push` `tags: ['[0-9]+.[0-9]+.[0-9]+']`.
- Checkout with `fetch-depth: 0`, `fetch-tags: true`.
- **Signed-tag gate** before anything else:
  ```bash
  gpg --import .github/release-signers.asc
  git verify-tag "$GITHUB_REF_NAME"   # fails on unsigned/lightweight/untrusted-key tags
  ```
- `VERSION="$GITHUB_REF_NAME"`; assert it does **not** end with `-SNAPSHOT`.
- Setup JDK 25; `./gradlew :SwiftKitCore:publish :SwiftKitFFM:publish -PreleaseBuild=true -PswiftkitVersion=$VERSION`
  (release staging URL), same four secrets in `env`.
- **Stage, manual finish** (ServiceTalk's curl close against our namespace):
  ```bash
  BEARER=$(printf "%s:%s" "$SONATYPE_USER" "$SONATYPE_TOKEN" | base64)
  curl -i --retry 5 -H "Authorization: Bearer $BEARER" -X POST \
    https://ossrh-staging-api.central.sonatype.com/manual/upload/defaultRepository/org.swift.swiftjava
  echo "Finish the release at https://central.sonatype.com/publishing/deployments"
  ```

### 6. Docs / release-script touch-ups

- `scripts/release.sh`: update the manual step it prints to explicitly instruct
  `git tag -s <version> -m "Release <version>"` (signed, annotated) and note that pushing the tag
  triggers `publish-release.yml`. No functional change to its flow.
- Add a short `RELEASING.md` (or a README section) documenting: required GitHub secrets, how to add a
  maintainer public key to `.github/release-signers.asc`, and the "click to finish in Central Portal"
  final step.

## GitHub secrets to configure (out-of-band, by the user)

| Secret | Purpose |
|---|---|
| `ORG_GRADLE_PROJECT_SIGNINGKEY` | ASCII-armored GPG **private** key for artifact signing |
| `ORG_GRADLE_PROJECT_SIGNINGPASSWORD` | passphrase for that key |
| `SONATYPE_USER` | Central Portal token username |
| `SONATYPE_TOKEN` | Central Portal token |

Also required once at Sonatype: verify the **`org.swift.swiftjava`** namespace for the Central Portal
account. Note the built-in `GITHUB_TOKEN` needs no configuration.

## Files to create / modify

- **Create** `BuildLogic/src/main/kotlin/build-logic.published-library-conventions.gradle.kts`
- **Modify** `SwiftKitCore/build.gradle.kts`, `SwiftKitFFM/build.gradle.kts` (apply convention, drop
  inline publishing, group now inherited)
- **Create** `scripts/next-snapshot-version.sh`
- **Create** `.github/release-signers.asc`
- **Create** `.github/workflows/publish-snapshot.yml`, `.github/workflows/publish-release.yml`
- **Modify** `scripts/release.sh` (print signed-tag instruction), **create** `RELEASING.md`

## Verification

1. **Local dry run, no secrets** (signing auto-skipped), publish to mavenLocal:
   `./gradlew :SwiftKitCore:publishToMavenLocal :SwiftKitFFM:publishToMavenLocal -PswiftkitVersion=0.6.1-SNAPSHOT`
   then inspect `~/.m2/repository/org/swift/swiftjava/swiftkit-core/0.6.1-SNAPSHOT/` - expect the jar,
   `-sources.jar`, `-javadoc.jar`, and a POM with the required metadata, and **no** OS classifier in
   the filename.
2. **Version guards:** `./gradlew ... -PreleaseBuild=true -PswiftkitVersion=0.6.1-SNAPSHOT` must fail;
   `-PswiftkitVersion=0.6.1` must pass.
3. **Signing locally:** export `ORG_GRADLE_PROJECT_signingKey`/`...signingPassword` from a test GPG
   key and confirm `.asc` signatures appear next to each artifact in mavenLocal.
4. **Snapshot version script:** `scripts/next-snapshot-version.sh` prints `0.6.1-SNAPSHOT` on current
   `main`.
5. **Signed-tag gate:** with a trusted key in `.github/release-signers.asc`, `git verify-tag` on a
   `git tag -s`-created tag succeeds; a lightweight tag or an untrusted signer fails.
6. **End to end:** merge a PR to `main` -> snapshot workflow uploads to
   `central.sonatype.com/repository/maven-snapshots`; push a signed `X.Y.Z` tag -> release workflow
   verifies the tag, stages to Central, prints the finish URL; confirm the deployment appears (and can
   be released) at `central.sonatype.com/publishing/deployments`.
