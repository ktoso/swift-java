# Releasing swift-java

This document covers the one-time prerequisites for a maintainer to publish
artifacts to Maven Central, the CI workflows that perform the publishing, and
the recurring flow for cutting a release.

For the *what* (coordinates, classifiers, repository URLs, consumption
snippets), see [`PUBLISHING.md`](./PUBLISHING.md).

## One-time prerequisites

### Obtain Maven Central credentials

In the Sonatype Central Portal at https://central.sonatype.com:

1. Click your username → **View Account**.
2. **Generate User Token**. Save the username + password tuple — these go
   into the `JRELEASER_MAVENCENTRAL_USERNAME` / `JRELEASER_MAVENCENTRAL_PASSWORD`
   secrets (release path) and `JRELEASER_NEXUS2_USERNAME` /
   `JRELEASER_NEXUS2_PASSWORD` secrets (snapshot path; the same user-token
   typically works for both).

If snapshot uploads return 401, file an OSSRH JIRA ticket linking the
verified Portal namespace to your account so the legacy snapshot endpoint
recognizes it.

### Generate and export a PGP signing key

Maven Central requires every artifact to be PGP-signed. JReleaser reads the
key material from environment variables (`JRELEASER_GPG_*`).

```bash
# Generate a key (default options are fine; pick a strong passphrase).
gpg --full-generate-key

# List keys to find the long ID.
gpg --list-secret-keys --keyid-format=long
# Look for: sec   rsa4096/<KEY_ID> ...

# Export both halves as ASCII-armored text.
gpg --armor --export <KEY_ID>             > public.asc
gpg --armor --export-secret-key <KEY_ID>  > private.asc

# Publish the public half to a keyserver so Maven Central can verify
# signatures during release validation.
gpg --keyserver keyserver.ubuntu.com --send-keys <KEY_ID>
gpg --keyserver keys.openpgp.org      --send-keys <KEY_ID>
```

Don't lose `private.asc` or the passphrase — together they're the only way
to sign future releases under this key. Storing them in a team password
manager is the typical path.

### Configure repository secrets

In the GitHub repo's **Settings → Secrets and variables → Actions**, create:

| Secret                            | Value                                                                            |
| --------------------------------- | -------------------------------------------------------------------------------- |
| `JRELEASER_MAVENCENTRAL_USERNAME` | Portal user-token name                                                           |
| `JRELEASER_MAVENCENTRAL_PASSWORD` | Portal user-token password                                                       |
| `JRELEASER_NEXUS2_USERNAME`       | Same as above (or OSSRH-issued credential)                                       |
| `JRELEASER_NEXUS2_PASSWORD`       | Same as above                                                                    |
| `JRELEASER_GPG_PUBLIC_KEY`        | Contents of `public.asc` (entire armored block, including BEGIN/END lines)       |
| `JRELEASER_GPG_SECRET_KEY`        | Contents of `private.asc` (entire armored block)                                 |
| `JRELEASER_GPG_PASSPHRASE`        | The passphrase used at key generation                                            |

The publish workflows verify all required secrets are present in their
first step and fail fast if any are empty, so a misconfiguration is caught
within seconds rather than after the build runs.

> Don't paste GPG key contents into a chat, ticket, or shell history. Copy
> directly from `public.asc` / `private.asc` into the GitHub Secrets UI.

### Verify locally before the first real release

```bash
./gradlew :SwiftKitCore:publishToMavenLocal \
          :SwiftKitFFM:publishToMavenLocal \
          :SwiftKitCoreNative:publishToMavenLocal \
          :SwiftKitFFMNative:publishToMavenLocal

ls ~/.m2/repository/org/swift/swiftjava/    # confirm artifacts landed

./gradlew stageForJReleaser
find build/staging-deploy -type f           # confirm staged artifacts

# Validate JReleaser config offline (dummy creds; no upload).
JRELEASER_GPG_PUBLIC_KEY=dummy JRELEASER_GPG_SECRET_KEY=dummy \
JRELEASER_GPG_PASSPHRASE=dummy \
JRELEASER_NEXUS2_USERNAME=dummy JRELEASER_NEXUS2_PASSWORD=dummy \
JRELEASER_MAVENCENTRAL_USERNAME=dummy JRELEASER_MAVENCENTRAL_PASSWORD=dummy \
JRELEASER_GITHUB_TOKEN=dummy \
./gradlew jreleaserConfig
```

To exercise signing locally with the real key (still no upload):

```bash
export JRELEASER_GPG_PUBLIC_KEY="$(gpg --armor --export <KEY_ID>)"
export JRELEASER_GPG_SECRET_KEY="$(gpg --armor --export-secret-keys <KEY_ID>)"
export JRELEASER_GPG_PASSPHRASE='<your-passphrase>'
./gradlew stageForJReleaser
./gradlew jreleaserSign
ls build/jreleaser/sign/
```

## CI workflows

Two GitHub Actions workflows handle publishing:

| Workflow                                                                            | Trigger                                                              | What it does                                                                                                                                                                       |
| ----------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`.github/workflows/snapshot-publish.yml`](.github/workflows/snapshot-publish.yml)  | Push to `main`; manual `workflow_dispatch`                           | One Java publish job + matrix of native publish jobs (one per platform classifier). Snapshots route to the Sonatype snapshots repo.                                                |
| [`.github/workflows/release-publish.yml`](.github/workflows/release-publish.yml)    | Push of a `N.N.N` tag; manual `workflow_dispatch` with `ref` input   | Same shape as snapshot, plus tag/version match validation. Releases stage to Central Portal deployments for manual finalization.                                                   |

Each workflow has three job groups:

1. **`publish-java`** — single Linux container job. Runs `:SwiftKitCore:publish :SwiftKitFFM:publish` to stage to `build/staging-deploy/`, then `./gradlew jreleaserDeploy`. Publishes the classifier-less Java jars. Verifies all required secrets up-front so missing credentials fail fast (within seconds).
2. **`publish-natives-linux`** — matrix of platform/arch entries; each entry computes the Maven classifier as `<platform>-swift_${SWIFT_TOOLCHAIN_VERSION}-<arch>` and runs `:SwiftKitCoreNative:publish :SwiftKitFFMNative:publish` with `-PnativeClassifier=<classifier> -PswiftVersion=<X.Y>` (and `-PnativeBuildSdk=<sdk>` for the static-SDK variants), then `./gradlew jreleaserDeploy`.
3. **`publish-natives-macos`** — single macOS arm64 job, mirrors the Linux pattern with the fixed classifier `osx-aarch_64`.

All native jobs depend on `publish-java` succeeding. **Each matrix job creates its own Sonatype Central Portal deployment** — releases require visiting https://central.sonatype.com/publishing/deployments and clicking Publish on each one. Snapshot uploads are silent (no clicks needed).

The snapshot workflow has a final **`smoke-test-snapshot`** job that depends on every publish job. It creates a throwaway Gradle project that depends on the just-published `-SNAPSHOT` artifacts and resolves the `runtimeClasspath` configuration. This catches POM/metadata mistakes that pass JReleaser validation but break downstream consumers — for example, if a classifier is mis-spelled or a dependency reference is wrong.

The Swift toolchain version is parameterized in each workflow as a top-level
`SWIFT_TOOLCHAIN_VERSION` env var; when bumping Swift, update that value
**and** the matrix `swift:X.Y-*` container references (GitHub Actions does not
expand env into matrix `include` containers).

## Cutting a release

1. Run `./scripts/release.sh` from a clean `main`. The script prompts for a
   version, creates a `release/<version>` branch, pins
   `swift-java-jni-core` to its latest release tag in `Package.swift`,
   verifies Swift + Gradle builds, and pushes the branch.
2. Open a pull request for the `release/<version>` branch. Run any
   additional qualification (downstream smoke tests, sample-app runs).
3. Merge the PR.
4. Tag the merge commit on `main` with the same version and push the tag:

   ```bash
   git tag -s <version> -m <version>
   git push origin <version>
   ```

   Pushing the tag triggers `.github/workflows/release-publish.yml`. The
   version derivation in `build.gradle.kts` resolves the project to
   `<version>` (no `-SNAPSHOT`); JReleaser routes uploads to the Central
   Portal release deployer.
5. Wait for the workflow to finish. **Each matrix entry creates its own
   USER_MANAGED deployment.** Visit
   https://central.sonatype.com/publishing/deployments and click **Publish**
   on each. Until clicked, nothing is visible on Maven Central.
6. Once everything is published, run `./scripts/release.sh --next` to point
   `swift-java-jni-core` back at `main` for the next development cycle.

> **Mistakes are permanent.** A `<groupId>:<artifactId>:<version>:<classifier>`
> tuple cannot be unpublished or republished once finalized. If something
> ships wrong, fix the bug and tag `<next-patch>` instead.

## Known operational caveats

- **Snapshot uploads can be silently slow.** Allow up to ~1 minute between
  `jreleaserDeploy` succeeding and the artifact appearing at
  `central.sonatype.com/repository/maven-snapshots/...`. The
  `smoke-test-snapshot` job in `snapshot-publish.yml` polls for visibility
  with a 5-minute total budget before failing.
- **GPG key rotation.** When rotating the signing key, regenerate the three
  `JRELEASER_GPG_*` secrets and publish the new public half to the same
  keyservers as the old key. Old releases stay validly signed by the old
  key (signatures don't rotate).
