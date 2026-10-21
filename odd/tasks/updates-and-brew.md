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
- [x] U1 Disable App Sandbox + one-time container migration (settings, notified.json) with tests — delegated — `144f19e`; `PRODUCT_NAME = Matchday` (module `matchday`) → `Matchday.app`; RED missing type → GREEN; live: favorites/appearance migrated to `~/Library/Preferences`, container kept
- [x] U2 Sparkle updater: SPM 2.9.6, Info.plist keys (`Resources/Matchday-Info.plist`), AppUpdating/SparkleUpdateChecker/AutomaticUpdateChecks/UpdatePolicy, context menu item, Settings Updates card, tests — delegated (same writer as U1) — `9c134b6`; RED → GREEN 296 tests; parent spot check TEST SUCCEEDED; codesign: no app-sandbox entitlement, Sparkle.framework embedded
- [ ] U3 Release pipeline: scripts (release/appcast/ExportOptions), release workflow, RELEASING.md, README brew section — delegated
- [x] U4 Tap: `Casks/matchday.rb`, bump.yml + ci.yml entries in homebrew-tap — delegated (parallel, other repo) — homebrew-tap `feat/matchday-cask` `925699a` (not pushed); `version "0.0.0"` + zero sha256 placeholder so the first real tag always bumps; bump skips matchday until a release exists (`unreleased: true`); CI runs offline audit only for matchday until first release
  - Follow-up after first release: add matchday to ci.yml online audit + install/zap, drop `unreleased` flag.

## Checks
- `xcodebuild -project matchday.xcodeproj -scheme matchday -destination 'platform=macOS' test -only-testing:matchdayTests`
- Build + live launch; `codesign -d --entitlements -` shows no app-sandbox.
- `bash -n` / shellcheck (if available) on scripts; `brew style`/`brew audit` on the cask if feasible.

## Progress
- 2026-10-21: exploration done; branch created; feature doc created.

## Next step
U1+U2 writer and U4 tap writer in parallel; then U3.
