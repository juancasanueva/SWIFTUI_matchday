# Feature: macOS Matchday (menu bar app)

Locator: `odd/tasks/macos-matchday.md` · Engram mirror: `odd/macos-matchday/tasks`
Branch: `feat/macos-matchday`

## Objective
Port the Omarchy "Matchday" plugin (`original/`, gitignored reference) to a native
macOS SwiftUI menu bar app with full feature parity: follow soccer teams, fixtures,
live scores, results, standings, where-to-watch, and notifications.

## Problem / Why
The current Xcode project is the default SwiftData template. The user wants the full
Matchday functionality natively on macOS, for personal use.

## Scope
- Data: ESPN public site API (keyless), leagues `esp.1`, `ita.1`, `eng.1`, `usa.1`,
  `uefa.champions`, `uefa.nations`.
- Menu bar label: ball icon, upcoming/live dot, optional live score text.
- Panel (MenuBarExtra `.window`): Following / Matches / Tables / Teams tabs + settings.
- Where-to-watch from bundled `broadcasters.json` + ESPN US TV names.
- Notifications: kickoff reminder, goals, full time (UNUserNotificationCenter).
- Tiered polling + disk cache of HTTP responses and crests.
- Keyboard shortcuts in the panel (1–4, h/l, j/k, r, Esc).

## Constraints / decisions
- Personal use: unofficial ESPN API is acceptable (not targeting App Store).
- Persistence: UserDefaults for settings/favorites; JSON files in Caches for HTTP cache.
  SwiftData template removed.
- Country for where-to-watch: `Locale.current.region`, overridable in settings.
- Dropped Linux-only features: Omarchy IPC `status`, middle/right click on bar.
- Added UI for `kickoffLead` and enabled `leagues` (not editable in original).
- App target: sandbox + outgoing network entitlement, `LSUIElement = YES`.
- Swift 5 mode, MainActor default isolation (existing project settings).
- Technical artifacts in English.

## Acceptance criteria
- App runs as menu-bar-only app; no Dock icon, no main window.
- All four tabs render real ESPN data matching original behavior/screenshots.
- Following/unfollowing persists across launches.
- Notifications fire for followed teams per settings.
- Unit tests cover decoding/normalization, polling hotness/TTLs, where-to-watch, ordering.

## Checks
- `xcodebuild -project matchday.xcodeproj -scheme matchday -destination 'platform=macOS' build`
- `xcodebuild ... test -only-testing:matchdayTests`
- Test-first where deterministic (parsing, schedulers, where-to-watch); UI via build + manual run.

## Delivery
- Forecast: ~4,500 authored changed lines (exceeds ~400 budget) → strategy `ask-on-risk`;
  chain strategy: `feature-branch-chain` (user choice 2026-10-21).
- Tracker branch: `feat/macos-matchday` (draft/no-merge tracker PR when user opens PRs).
- Slices: one child branch per task, chained: `feat/macos-matchday-tNN-<slug>` branched from the
  previous task branch (T1 from the tracker). Push/PR creation is the user's decision.

## Architecture (screaming + hexagonal, container/presentational)
- `matchday/App/` composition root (`matchdayApp`, `AppEnvironment`).
- `matchday/Domain/` pure models + ports (protocols) + pure logic (ordering, hotness, status).
- `matchday/Data/ESPN/` DTOs, mappers, client adapter; `Data/Cache/` disk HTTP cache;
  `Data/Settings/` UserDefaults store; `Data/Broadcasters/` where-to-watch + bundled JSON.
- `matchday/Application/` `@Observable` store + refresh scheduler (use cases).
- `matchday/Features/<MenuBar|Panel|Following|Matches|Tables|Teams|Settings>/` containers +
  presentational views; `Features/Shared/` reusable atoms (crest, league dot, chip, form box, pill).
- Tests: Swift Testing in `matchdayTests/`, JSON fixtures in `matchdayTests/Fixtures/`.

## Tasks
- [x] T0 Repo hygiene: untrack xcuserdata/.DS_Store — inline — commit `6d15413` — assess: medium, under_budget
- [x] T1 Project setup: remove SwiftData template, MenuBarExtra skeleton, LSUIElement, network entitlement — delegated (bundled with T2/T3 writer: preparation reading) — `feat/macos-matchday-t01-setup` `8c96449` — build ok, 1 test
- [x] T2 Domain models + ESPN DTOs + normalization (events, standings, teams, schedules) with fixture tests — delegated (2+ non-trivial files) — `feat/macos-matchday-t02-domain` `0b388da` — RED 15 failing vs stub → GREEN 19 tests
- [x] T3 HTTP client + disk cache + tiered polling scheduler (hotness, TTLs, status ok/loading/offline/stale) with tests — delegated (2+ non-trivial files) — `feat/macos-matchday-t03-data` `47137ac` — RED (missing types) → GREEN 55 tests; parent spot check: test run TEST SUCCEEDED
  - Assess (base `main`, committed-only): medium, `slice_budget_reached` (2,646 lines) → consent granted → native review (reliability lens) **approved + acknowledged** (lineage `review-8966a2091423f10f`). Reviewed boundary advances to T3 head.
  - Advisory follow-ups (non-blocking): R3 stale errors never pruned (`MatchRepository.swift:59-67`, WARNING); R3 decode-failure path untested (`MatchRepository.swift:220-230`, SUGGESTION) → folded into T6.
  - Second review pass on `main..c901708` (hook-triggered, lineage `review-1d552ad67a83c623`): approved + acknowledged; extra follow-ups R3-reentrant-refresh (WARNING) and R3-client-error-branches → folded into T6.
- [x] T4 Settings & favorites store (UserDefaults), league config — delegated — `feat/macos-matchday-t04-settings` `74de08c` — RED compile fail → GREEN 77 tests
- [x] T5 Where-to-watch (bundled broadcasters.json, ESPN aliases, spanish filter, country) with tests — delegated — `feat/macos-matchday-t05-watch` `da71021` — RED → GREEN
- [x] T6 App store/view model aggregating data (following cards ordering, live elsewhere, matches by day, tables) with tests; + review follow-ups (prune stale errors, decode-failure test, coalesce overlapping refreshes, client error-branch tests) — delegated — `feat/macos-matchday-t06-store` `0670d06`, `ef53ee1`, `bc5e90e` (chmod 644 broadcasters.json) — GREEN 163 tests; parent spot check TEST SUCCEEDED
  - Assess (base `c901708`): high `executable_mode` (755 JSON) → fixed → medium `slice_budget_reached` (2,582 lines) → consent granted → review (`review-7f3a9946a2462d6b`) **approved + acknowledged**. Boundary → `bc5e90e`.
  - Advisory follow-ups → T7: R3-join-drops-caller-intent (`MatchRepository.swift:63-71`, WARNING); R3-overlap-test-nondeterministic (`MatchRepositoryTests.swift:211-221`, SUGGESTION).
  - Hook-triggered whole-branch review (`main..3a125d2`, 5,218 lines) stopped `lens_context_budget_exceeded` (terminal, no authority created); covered by the per-slice reviews above.
- [x] T7 Menu bar label (icon, dot, pulse, live score) + panel shell, header, tab bar + T6 review follow-ups — delegated — `feat/macos-matchday-t07-shell` `efe7b34`, `b8ef639` — RED joined-refresh test → GREEN; launch: panel opens with live ESPN data
- [x] T8 Following tab (team cards, form, countdown, watch pills, last/then, live events) — delegated — `feat/macos-matchday-t08-following` `c18cbe9` — view exception: build + ImageRenderer PNGs vs screenshots
- [x] T9 Matches tab (filters, day sections, results, rows) — delegated — `feat/macos-matchday-t09-matches` `c1697be`, `cc7f318` — GREEN 166 tests; parent spot check TEST SUCCEEDED; launch ok
  - Assess (base `bc5e90e`): medium `slice_budget_reached` (1,902 lines) → consent granted → review (`review-d7b8ee73355a7540`) **approved + acknowledged**. Boundary → `cc7f318`.
  - Advisory SUGGESTIONs → T13: `MenuBarLabel.swift:53-59`, `MenuBarLabel.swift:33-36`, `MatchesTab.swift:65-71`, `Theme.swift:76-80`, `AppEnvironment.swift:37-41`.
  - Open: menu bar dot/pulse/live text not visually verified (no followed team; status item hidden behind custom menu bar); `.help` tooltip likely ignored on MenuBarExtra labels.
  - Hook-triggered whole-branch review (`main..19371cc`, 7,049 lines) → consent granted → `lens_context_budget_exceeded` (terminal, no authority); covered by slice reviews.
- [x] T10 Tables tab (league chips, groups, zones, legend, follow toggle) — delegated — `feat/macos-matchday-t10-tables` `67b41e7` — RED pickerLeague compile fail → GREEN; live: matches screenshot, follow toggle works
- [x] T11 Teams tab + Settings section (grid, toggles, country picker, kickoff lead, leagues, launch at login, test notif stub, refresh) — delegated — `feat/macos-matchday-t11-teams` `83d3bd0`, `6d0d6a4` — RED → GREEN 179 tests; parent spot check TEST SUCCEEDED
  - Assess (base `cc7f318`): medium `slice_budget_reached` (1,152 lines) → consent granted → review (`review-ef85295d450b1a29`) **approved + acknowledged**. Boundary → `6d0d6a4`.
  - Advisory → T12/T13: test-notification no-op (`MatchdayStore.swift:146-149`, WARNING, resolved by T12); locale-dependent country order test (`MatchdayStoreTests.swift:156-162`); untested empty message/refresh (`TablesTab.swift:72-76`).
  - Open: zone color contrast fallback missing (white zone invisible); league chip selection resets across tabs; launch-at-login verified by unit tests only.
  - Hook-triggered whole-branch review (`main..a3129b4`, 8,163 lines) → consent granted → `lens_context_budget_exceeded` (terminal); covered by slice reviews.
- [x] T12 Notifications (kickoff, goal, full time, dedupe store, open match on click) with tests — delegated — `feat/macos-matchday-t12-notifications` `76579b1` — RED compile fail → GREEN 170 tests; live: permission + "GOAL! Matchday" banner shown
- [x] T13 Crest image cache, keyboard shortcuts, zone contrast, status-item tooltip, app icon, README, review suggestions — delegated — `feat/macos-matchday-t13-polish` `8b4417f`, `5cd4ef2`, `5569e18`, `2ea42fa` — RED → GREEN 188 tests; live: shortcuts, crest disk cache across relaunch, tooltip
  - Assess (base `6d0d6a4`): medium `slice_budget_reached` (1,734 lines) → consent granted → review (`review-92a751f5047f0fd2`) **approved + acknowledged**. Boundary → `2ea42fa`.
  - Follow-up fixed inline (WARNING R3-crest-transient-failure-marker): `c5d2a3e` — RED new test failed → GREEN full suite; assess `under_budget` (23 lines, pending in next slice).
  - Remaining advisory SUGGESTIONs (not done): simultaneous goals in one refresh produce a single alert (`NotificationPlanner.swift:126-128`); status-item tooltip initial lookup (`MenuBarLabel.swift:54-56`).

## Outcome (2026-10-21)
All tasks T0–T13 done on the chain `feat/macos-matchday-t01-setup` → … → `feat/macos-matchday-t13-polish`
(tracker `feat/macos-matchday`). 188+1 unit tests green. Five slice reviews approved.
Not yet verified live: menu bar dot/pulse/live score during a real live match.
Pushed 2026-10-21: tracker draft PR #1 (`feat/macos-matchday` → `main`), child PRs #2–#14 (T1–T13, each based on its parent branch). Merging is the user's decision.

## Progress
- 2026-10-21: Exploration done (ESPN endpoints, features, screenshots mapped). Branch created. T0 done.

## Next step
Push the chain and open the tracker + child PRs (user decision); watch a live match to verify the menu bar dot/pulse/score.
