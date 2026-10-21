# Feature: Updates (Sparkle) and Homebrew distribution

Locator: `odd/tasks/updates-and-brew.md` · Engram mirror: `odd/updates-and-brew/tasks`
Branch: `feat/updates-and-brew` (from `main` at `d16e885`)

## Objective
Port system-monitor's "Check for Updates" (Sparkle 2) and Homebrew cask distribution to Matchday.

## Problem / Why
Matchday has no way to ship new versions to the user's Mac; system-monitor already has a proven
release → GitHub Release → appcast (GitHub Pages) → Sparkle / Homebrew tap pipeline.

## Reference
`/Users/juancasanueva/programming/swiftUI/system-monitor` (read-only): Sparkle 2.9.6 via SPM
(exactVersion), `AppUpdating` port + `SparkleUpdateChecker`, `AutomaticUpdateChecks`
(`updates.automaticChecksEnabled`, opt-in), `UpdatePolicy`, `UpdateCheckPresentation`, context menu
"Check for Updates…", Settings "Updates" section; `scripts/release.sh`, `scripts/appcast.sh`,
`scripts/ExportOptions.plist`, `.github/workflows/release.yml`, `RELEASING.md`.
Tap: `juancasanueva/homebrew-tap` (local clone `/Users/juancasanueva/programming/swiftUI/homebrew-tap`),
`Casks/*.rb`, `.github/workflows/bump.yml` (6-hourly matrix), `ci.yml`.

## Decisions (2026-10-21)
- App Sandbox **off** (option A, user "go ahead" on the recommendation) to match system-monitor's
  proven Sparkle/release setup; hardened runtime stays on.
- One-time migration of settings/favorites (and notification dedupe store) from the old sandbox
  container on first non-sandboxed launch.
- Reuse the shared Sparkle EdDSA key (public key `jqReS/cOvK94pbRz/4DwMBTRMwh/0Nf5OJZ5SAfZDVs=`).
- Feed: `https://juancasanueva.github.io/SWIFTUI_matchday/appcast.xml` (GitHub Pages via Actions).
- Release asset: `Matchday-<version>.zip`; version from tag `vX.Y.Z`, build from run number.
- Cask `matchday` in `juancasanueva/tap`; tap changes committed locally, pushing is the user's call.

## Scope
- In: sandbox removal + migration, Sparkle updater + UI, release scripts/workflow/docs, README brew
  install section, tap cask + bump/ci entries.
- Out: actually cutting a release, adding repo secrets, enabling Pages (user actions).

## User actions required (cannot be automated here)
1. Add 7 repo secrets to `juancasanueva/SWIFTUI_matchday`: `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`,
   `KEYCHAIN_PASSWORD`, `APPLE_API_KEY_P8`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `SPARKLE_PRIVATE_KEY`.
2. GitHub Pages: source "GitHub Actions"; `github-pages` environment tag rule `v*`.
3. Push the tap commit (or approve the parent pushing it).
4. Tag the first release `v1.0.0` (or later) from its own commit.

## Tasks
- [ ] U1 Disable App Sandbox + one-time container migration (settings, notified.json) with tests — delegated
- [ ] U2 Sparkle updater: SPM 2.9.6, Info.plist keys, AppUpdating/SparkleUpdateChecker/AutomaticUpdateChecks/UpdatePolicy, context menu item, Settings Updates section, tests — delegated (with U1, same writer)
- [ ] U3 Release pipeline: scripts (release/appcast/ExportOptions), release workflow, RELEASING.md, README brew section — delegated
- [ ] U4 Tap: `Casks/matchday.rb`, bump.yml + ci.yml entries in homebrew-tap (local commit) — delegated (parallel, other repo)

## Checks
- `xcodebuild -project matchday.xcodeproj -scheme matchday -destination 'platform=macOS' test -only-testing:matchdayTests`
- Build + live launch; `codesign -d --entitlements -` shows no app-sandbox.
- `bash -n` / shellcheck (if available) on scripts; `brew style`/`brew audit` on the cask if feasible.

## Progress
- 2026-10-21: exploration done; branch created; feature doc created.

## Next step
U1+U2 writer and U4 tap writer in parallel; then U3.
