# Releasing Matchday

How a version of Matchday becomes a notarized download, a Sparkle update and a
Homebrew cask, and what to do when a run fails. The pipeline is a port of
[System Monitor](https://github.com/juancasanueva/SWIFTUI_system_monitor)'s,
which has already shipped through it.

## 1. How a release happens

A pushed `v*` tag is the **only** thing that publishes. The workflow holds a
Developer ID certificate, an App Store Connect key and the Sparkle signing key,
so it has no other trigger a contributor could reach.

| File | Owns |
|---|---|
| `.github/workflows/release.yml` | The runner, the secrets, the ephemeral keychain, cleanup, and publication (GitHub Release + Pages) |
| `scripts/release.sh` | The build sequence: archive → export → package → notarize → staple → verify |
| `scripts/appcast.sh` | The update feed: download and verify the pinned Sparkle tools, fetch the live feed, sign one zip, merge one item, emit |
| `scripts/ExportOptions.plist` | Developer ID export, manual signing, team `Z3S5JK8E38` |

Neither script contains `git` or `gh`, so neither can tag, publish or retract
anything; `matchdayTests/ReleasePipelineTests.swift` asserts that, along with
the asset name, the feed URL, the seven secrets and the minimum system version.

## 2. One-time setup

None of this blocks merging the pipeline. All of it blocks the first release.

1. **The repository stays public.** Release assets must be anonymously
   downloadable (Sparkle and Homebrew fetch them without credentials). The
   workflow refuses to run on a private repository.
2. **Seven repository secrets** in `juancasanueva/SWIFTUI_matchday`
   (Settings → Secrets and variables → Actions), named exactly as in System
   Monitor; the same values can be reused:

   | Secret | Value |
   |---|---|
   | `BUILD_CERTIFICATE_BASE64` | `base64 -i DeveloperID.p12` (Developer ID Application certificate **with its private key**) |
   | `P12_PASSWORD` | The password used when exporting the `.p12` |
   | `KEYCHAIN_PASSWORD` | Any strong string; it protects the run's throwaway keychain |
   | `APPLE_API_KEY_P8` | The full contents of the App Store Connect API key (`.p8`, Developer role) |
   | `APPLE_API_KEY_ID` | That key's id |
   | `APPLE_API_ISSUER_ID` | That key's issuer id |
   | `SPARKLE_PRIVATE_KEY` | The shared Sparkle EdDSA private key (see 4) |

3. **GitHub Pages, source = GitHub Actions.** Settings → Pages → Build and
   deployment → Source: **GitHub Actions**. Pages serves
   `https://juancasanueva.github.io/SWIFTUI_matchday/appcast.xml`, the feed in
   `Resources/Matchday-Info.plist` (`SUFeedURL`). Then Settings → Environments →
   `github-pages` → Deployment branches and tags → add a **tag** rule `v*`. The
   environment is created with a branch policy, and without the tag rule the
   deploy step fails at the end of an otherwise successful release.
4. **The Sparkle key is shared.** Matchday's `SUPublicEDKey`
   (`jqReS/cOvK94pbRz/4DwMBTRMwh/0Nf5OJZ5SAfZDVs=`) is the same public key System
   Monitor and Home Cellar ship, so `SPARKLE_PRIVATE_KEY` is the same private key
   their release jobs use. Export it from the login Keychain with Sparkle 2.9.6's
   `./bin/generate_keys -x sparkle-private.key` if you do not already have it
   offline. Losing it severs the update channel of **every** app that shares it;
   the public key is not a secret.
5. **The Homebrew cask.** `Casks/matchday.rb` lives in `juancasanueva/tap`
   (`juancasanueva/homebrew-tap`), with a `matchday` entry in its `bump.yml`
   matrix and `ci.yml`. Push or merge that tap change before the first release.
   The tap pulls new versions on a schedule from this repository's
   `releases/latest`; the release job never pushes to it. After the first
   release, add `matchday` to the tap CI's online audit and install/zap jobs and
   drop its `unreleased` flag in `bump.yml`.

## 3. Cutting a release

**Bump nothing in the project.** `MARKETING_VERSION` stays `1.0.0` and
`CURRENT_PROJECT_VERSION` stays `1` in `project.pbxproj`; the workflow stamps the
version from the tag (`vX.Y.Z` → `X.Y.Z`) and the build number from the run
number, which only increases, as Sparkle's version comparison needs. A local
Release build therefore always reports `1.0.0 (1)`.

**Every stable release is tagged on its own commit.** GitHub Pages keys a
deployment by commit and silently ignores a second deployment of the same one,
so a second stable tag on an already-deployed commit would publish a release the
feed never learns about. The workflow refuses that case before building.
Release runs share one concurrency group, so tags pushed close together queue
and each one merges into the feed the previous run deployed.

```sh
git switch main && git pull
git tag -a v1.0.0 -m "Matchday 1.0.0"
git push origin v1.0.0
```

Then watch the run in the Actions tab. Stages, in order: private-repository gate,
distinct-commit gate, Pin Xcode (26.6), keychain import, Archive, Export (gates
version and `arm64`), Package (`Matchday-<version>.zip`), Notarize, Staple and
repackage, Verify (Gatekeeper, staple, signature, hardened runtime, Developer ID
team, **no app-sandbox entitlement**, architecture, version, build, bundle name
and identifier, no release files inside the bundle), fetch the Sparkle tools and
the live feed, **Publish** (`gh release create --verify-tag --generate-notes`),
build the appcast, deploy to Pages, delete the keychain.

A tag with a hyphen (`v1.1.0-rc.1`) publishes a **prerelease** with no feed entry,
so installed copies are never offered it. That is how to rehearse the pipeline
against the real repository.

What every delivery channel binds to:

| Property | Value |
|---|---|
| Asset | `https://github.com/juancasanueva/SWIFTUI_matchday/releases/download/v<version>/Matchday-<version>.zip` |
| Bundle | `Matchday.app`, `Contents/MacOS/Matchday`, identifier `com.juancasanueva.matchday` |
| Signature | Developer ID Application, team `Z3S5JK8E38`, hardened runtime, no sandbox, notarized and stapled |
| Floor | macOS 15.6 (`MINIMUM_SYSTEM_VERSION` in `scripts/appcast.sh` equals `MACOSX_DEPLOYMENT_TARGET`), Apple silicon only |
| Feed | `https://juancasanueva.github.io/SWIFTUI_matchday/appcast.xml`, republished on every stable tag |

## 4. Local rehearsal

```sh
# Archive needs the Developer ID Application identity in the login keychain.
VERSION=1.0.0 BUILD_NUMBER=1 scripts/release.sh archive
VERSION=1.0.0 BUILD_NUMBER=1 scripts/release.sh export
VERSION=1.0.0 scripts/release.sh package

# `all` includes notarize, so the App Store Connect key is required.
VERSION=1.0.0 BUILD_NUMBER=1 \
ASC_KEY_PATH=~/.private_keys/AuthKey_XXXXXXXXXX.p8 ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=<issuer-uuid> \
scripts/release.sh all
```

Output goes to `build/` (override with `RELEASE_BUILD_DIR`); do not commit it.
`SIGNING_STYLE` defaults to `manual` and must match `signingStyle` in
`scripts/ExportOptions.plist`; the script refuses to run when they disagree.

The feed step rehearses the same way and publishes nothing:

```sh
GITHUB_REF_NAME=v1.0.0 SPARKLE_TOOLS_DIR=/tmp/sparkle-tools scripts/appcast.sh tools
GITHUB_REF_NAME=v1.0.0 FEED_URL=https://juancasanueva.github.io/SWIFTUI_matchday/appcast.xml \
CURRENT_FEED_FILE=/tmp/current-appcast.xml scripts/appcast.sh fetch
VERSION=1.0.0 BUILD_NUMBER=1 GITHUB_REF_NAME=v1.0.0 \
ASSET_URL=https://github.com/juancasanueva/SWIFTUI_matchday/releases/download/v1.0.0/Matchday-1.0.0.zip \
ZIP_PATH=build/Matchday-1.0.0.zip CURRENT_FEED_FILE=/tmp/current-appcast.xml \
SPARKLE_TOOLS_DIR=/tmp/sparkle-tools OUTPUT_DIR=/tmp/site \
SPARKLE_PRIVATE_KEY="$(cat ~/offline/sparkle-private.key)" scripts/appcast.sh
```

## 5. When a run fails

`gh release create` is the line: before it nothing is public, after it the
release exists.

**Before Publish** (gates, keychain, archive through verify, the two fetches):
nothing was published. A transient download failure needs only **Re-run failed
jobs**. Otherwise fix the cause, then delete and re-push the tag; the same commit
is fine because it never deployed:

```sh
git push --delete origin v1.0.0 && git tag -d v1.0.0
```

**After Publish** (build the appcast, Pages upload or deploy): the release and
its zip exist and may already be picked up by the tap, but no installed copy is
offered the version. Prefer **cutting the next patch** (`v1.0.1`) on a new commit.
If the cause was outside the repository (a secret, the `github-pages` tag rule, a
transient Pages failure), delete only the release and re-run the job. The
distinct-commit gate only refuses a commit whose Pages deployment **succeeded**;
a failed, cancelled or lost deployment leaves the commit free to deploy again:

```sh
gh release delete v1.0.0 --repo juancasanueva/SWIFTUI_matchday --yes
```

Never delete or unflag a release the feed already points at; withdraw a bad
release by publishing a higher version.

## 6. Troubleshooting

- **Notarization rejected.** The run prints the `notarytool log` for the
  submission. Usual causes: an unsigned nested binary, a missing hardened-runtime
  flag, the wrong identity. Nothing was published.
- **Keychain import failed.** `BUILD_CERTIFICATE_BASE64` is not a `.p12`
  exported with its private key, or `P12_PASSWORD` does not match it.
- **Signing failed locally.** `security find-identity -v -p codesigning` must
  list a *Developer ID Application* identity for team `Z3S5JK8E38`.
- **Verify: "the delivered bundle carries an app-sandbox entitlement".**
  Sparkle cannot replace a sandboxed app's bundle without its XPC installer
  setup, so the pipeline refuses one. Keep `ENABLE_APP_SANDBOX = NO`.
- **Pin Xcode fails.** The runner image dropped Xcode 26.6; update the pin to an
  Xcode the project builds with locally.
- **Stopped at the distinct-commit gate.** This commit already deployed the
  feed successfully. Put the new version on a new commit and tag that. If the
  gate reports an in-progress or unknown status instead, wait for that
  deployment to finish and re-run.
- **Fetch the live feed failed.** The feed answered something other than a
  usable 200 or a 404 (the first release) on every attempt. Nothing was
  published; check the URL and re-run.
- **Fetch the Sparkle tools failed.** A transient download failure (re-run), or
  the tarball no longer matches the pinned SHA-256: do not update the digest
  without finding out why.
- **Build the appcast failed.** Usually `SPARKLE_PRIVATE_KEY`. The release
  already exists; see "After Publish".
- **The run is green but the feed is stale.** Usually the Pages CDN; compare the
  feed's `last-modified`. A hyphenated tag skips the feed by design.
- **`brew install --cask matchday` says an app is already there.** Use
  `brew install --cask --adopt matchday`.
