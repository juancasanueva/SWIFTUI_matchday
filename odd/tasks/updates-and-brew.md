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
- [x] U3 Release pipeline: scripts (release/appcast/ExportOptions), release workflow, RELEASING.md, README brew section — delegated — `fffe98e` (ci), `4aed1ac` (docs), `65aed2e` (ignore `build/`); RED 22 contract tests → GREEN; bash -n, shellcheck, plutil, actionlint OK; local archive/export/package rehearsal signed with Developer ID (Z3S5JK8E38); notarize/staple/verify not run
  - Deviations: name gate uses `CFBundleName` (no display name set); feed `minimumSystemVersion` 15.6 = deployment target.
- [x] U4 Tap: `Casks/matchday.rb`, bump.yml + ci.yml entries in homebrew-tap — delegated (parallel, other repo) — homebrew-tap `feat/matchday-cask` `925699a` (not pushed); `version "0.0.0"` + zero sha256 placeholder so the first real tag always bumps; bump skips matchday until a release exists (`unreleased: true`); CI runs offline audit only for matchday until first release
  - Follow-up after first release: add matchday to ci.yml online audit + install/zap, drop `unreleased` flag.

  - Branch review (`main..5076cd4`, high, 4 lenses, lineage `review-c4c7a7a4f45c3c84`): **approved + acknowledged**. Warnings fixed test-first: `6beff66` (serialized feed deploys, retry after failed Pages deploy), `dcf190e` (migration marker only after success), `115460c` (explicit `SUScheduledCheckInterval` 86400). 330 tests green; parent spot check TEST SUCCEEDED.

## Delivery (2026-10-21)
- Merged to `main` (`ab32289`) and pushed. Tap `feat/matchday-cask` rebased onto tap `main` and pushed as `2448e42`.
- Secrets: all 7 set from local sources (Developer ID identity only, re-exported with a random password and probe-imported; API key `GF2PP6LZ22` + issuer from `~/Desktop/API KEY.txt`; random keychain password; shared Sparkle key verified against `SUPublicEDKey`). First Sparkle upload stored an error message (generate_keys refuses `/dev/stdout`) — caught and re-uploaded from a validated temp file.
- Pages: source GitHub Actions; `github-pages` policies `main` (branch) + `v*` (tag).
- Release `v1.0.0` on `ab32289`: run `39654804937` success; asset `Matchday-1.0.0.zip` (sha256 `e54322d0…`), `spctl`: Notarized Developer ID, stapled; appcast live with 1.0.0 (1), min 15.6, edSignature.
- Tap bump run `39655293210` success: `Casks/matchday.rb` → 1.0.0 with matching sha256.
- Follow-up: add matchday to tap `ci.yml` online audit + install/zap and drop `unreleased` flag.

## Post-release fixes (2026-10-21)
- 1.0.0/1.0.1: "Check for Updates…" always disabled — KVO observers lacked `.initial` (the port dropped it from system-monitor). Fixed `8941f2e`, released v1.0.2.
- 1.0.0–1.0.2: optimized builds crashed at launch (SIGSEGV in `ESPNEndpoint.cacheKey`) from a local function capturing the inout `TaskGroup` in `MatchRepository.run`. Debug builds were unaffected. Fixed `9e0cded`, released v1.0.3; the published build was smoke-launched for 20s. Tap bumped to 1.0.3.
- v1.0.4: first end-to-end "Check for Updates…" test (1.0.3 → 1.0.4).
- Proposed: smoke-launch the notarized app in `release.sh verify` (pending user decision).

## Checks
- `xcodebuild -project matchday.xcodeproj -scheme matchday -destination 'platform=macOS' test -only-testing:matchdayTests`
- Build + live launch; `codesign -d --entitlements -` shows no app-sandbox.
- `bash -n` / shellcheck (if available) on scripts; `brew style`/`brew audit` on the cask if feasible.

## Progress
- 2026-10-21: exploration done; branch created; feature doc created.

## Next step
All tasks done. User: review/merge branch, push tap branch, add 7 secrets, enable Pages (Actions + v* tag rule), tag first release.
