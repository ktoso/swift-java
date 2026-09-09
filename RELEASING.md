# Releasing swift-java

swift-java publishes `swiftkit-core` and `swiftkit-ffm` to Maven Central under the group
`org.swift.swiftjava`, using stock Gradle `maven-publish` + `signing` and Sonatype's Central Portal
OSSRH staging API. Publishing is automated via GitHub Actions; this document covers the one-time
setup and the human steps in the release flow.

## Required GitHub secrets

Configure these in the repository settings (Settings -> Secrets and variables -> Actions):

| Secret | Purpose |
|---|---|
| `ORG_GRADLE_PROJECT_SIGNINGKEY` | ASCII-armored GPG **private** key used to sign published artifacts (jars, poms) |
| `ORG_GRADLE_PROJECT_SIGNINGPASSWORD` | passphrase for that key |
| `SONATYPE_USER` | Sonatype Central Portal token username |
| `SONATYPE_TOKEN` | Sonatype Central Portal token |

`GITHUB_TOKEN` is provided automatically and needs no configuration.

Also required once, out of band: verify the `org.swift.swiftjava` namespace for the Central Portal
account at https://central.sonatype.com.

## How snapshots publish

Every merge to `main` (that touches source, not just docs/scripts) triggers
`.github/workflows/publish-snapshot.yml`, which computes the next snapshot version with
`scripts/next-snapshot-version.sh` (current release tag with the patch component bumped, plus
`-SNAPSHOT`) and publishes both modules to
`https://central.sonatype.com/repository/maven-snapshots/`.

## How releases publish

1. A maintainer runs `scripts/release.sh`, which pins dependencies, creates a release branch, and
   opens the way for a release PR.
2. Once the release PR is merged, the script prints the tagging step:
   ```
   git tag -s <version> -m "Release <version>"
   git push origin <version>
   ```
   The tag must be a **GPG-signed annotated tag** (`-s`), signed with a key listed in
   `.github/release-signers.asc` (see below).
3. Pushing the tag triggers `.github/workflows/publish-release.yml`, which:
   - imports `.github/release-signers.asc` and runs `git verify-tag` on the pushed tag, failing
     closed if the tag is unsigned, lightweight, or signed by an unrecognized key
   - publishes both modules to the Central Portal staging repository
   - calls the Central Portal "manual close" API and prints a link to
     https://central.sonatype.com/publishing/deployments
4. A maintainer opens that link and clicks "Publish" (or "Drop" if something looks wrong) to
   finish the release. This manual click is intentional; it is the last human checkpoint before
   artifacts become permanently public on Maven Central.

## Adding a maintainer's release-signing key

Only keys listed in `.github/release-signers.asc` can sign release tags that CI will accept.

To add yourself:

```bash
gpg --export --armor YOUR_KEY_ID >> .github/release-signers.asc
```

Then open a pull request with the change and get it reviewed and merged. Until at least one key
is present in that file, `publish-release.yml` cannot verify any tag and will fail closed, which
is the intended default for a repository with no signers configured yet.

## Local dry run (no secrets needed)

Signing is skipped automatically when `signingKey`/`signingPassword` are not set, so you can
verify the publication shape locally without any credentials:

```bash
./gradlew :SwiftKitCore:publishToMavenLocal :SwiftKitFFM:publishToMavenLocal -PswiftkitVersion=0.6.1-SNAPSHOT
```

Then inspect `~/.m2/repository/org/swift/swiftjava/swiftkit-core/0.6.1-SNAPSHOT/` (and the
`swiftkit-ffm` equivalent) for the jar, `-sources.jar`, `-javadoc.jar`, and a POM containing
name/description/url/license/scm/developers metadata, with no OS classifier in any filename
(the classifier convention is opt-in and off for both modules today).

The version-scheme guard can also be exercised locally:

```bash
# expected to fail: -SNAPSHOT version with a release build
./gradlew :SwiftKitCore:publishToMavenLocal -PreleaseBuild=true -PswiftkitVersion=0.6.1-SNAPSHOT

# expected to succeed: non-SNAPSHOT version with a release build
./gradlew :SwiftKitCore:publishToMavenLocal -PreleaseBuild=true -PswiftkitVersion=0.6.1
```
