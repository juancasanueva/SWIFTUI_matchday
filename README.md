# Matchday

A macOS menu bar app for following soccer teams: fixtures, live scores,
results, standings, where to watch, and notifications. It is a native SwiftUI
port of the Omarchy "Matchday" plugin.

Matchday lives only in the menu bar (no Dock icon, no main window). The ball
icon shows a dot when a followed team plays within 12 hours (red while live),
and optionally the live score next to it.

## Features

- **Following**: a card per followed team with the live or next match, a
  kickoff countdown, recent form, league position, where to watch, and the
  last and following matches. Other live games are listed below.
- **Matches**: fixtures and results by day across the enabled leagues,
  filtered by All, Mine (followed teams) or a single league.
- **Tables**: standings with qualification and relegation zones (grouped for
  MLS, the Champions League phase and the Nations League). Click a club to
  follow or unfollow it.
- **Teams**: a crest grid to follow teams, plus the settings: appearance (System,
  Light or Dark), watch country, Spanish-language broadcasts, kickoff reminder lead, goal and full-time
  alerts, live score in the bar, enabled leagues, launch at login, and a test
  notification.
- **Where to watch**: rights holders per country from a bundled
  `broadcasters.json`, plus ESPN's per-match US listings.
- **Notifications** for followed teams: a kickoff reminder, every goal (with
  the scorer), and the full-time result. Clicking one opens the match on ESPN.
  Alerts are remembered for 7 days, so a relaunch never repeats them.
- **About and context menu**: right-click the ball for About Matchday, Refresh
  and Quit; Settings also has an About Matchday button. The About window shows
  the version, data source, leagues and credits.
- **Keyboard** in the panel: `1`–`4` switch tabs, `h`/`l` cycle the league or
  filter chips, `j`/`k` scroll, `r` refreshes, `Esc` closes the panel.

Leagues: LaLiga, Serie A, Premier League, MLS, UEFA Champions League and UEFA
Nations League.

## Data source

Data comes from ESPN's public, keyless site API (`site.api.espn.com`) and its
crest CDN. The API is unofficial and undocumented: it may change or stop
working at any time. Matchday is a personal project and is not affiliated with
or endorsed by ESPN; it is not intended for the App Store.

Requests are polled on tiers (faster while a match is live) and mirrored to a
disk cache, so launches are instant and the app degrades gracefully offline.

## Install

Releases need macOS 15.6 or later on Apple silicon.

With [Homebrew](https://brew.sh):

```sh
brew trust juancasanueva/tap   # Homebrew 6.0.22 or later only
brew tap juancasanueva/tap
brew install --cask matchday
```

Homebrew 6.0.22 and later refuse to tap a third-party tap that carries a cask
until it is trusted, which is what the first line does; skip it on older
Homebrew. The unambiguous form is `brew install --cask juancasanueva/tap/matchday`.

**Already have `Matchday.app` in `/Applications`?** Homebrew refuses to
overwrite an app it did not place. Let it adopt the existing copy instead:

```sh
brew install --cask --adopt matchday
```

Or download the latest `Matchday-<version>.zip` from [Releases](../../releases),
unzip it, and drag `Matchday.app` to `/Applications`. The build is notarized and
stapled, so the first launch is an ordinary "Open" confirmation.

To update, `brew upgrade --cask matchday` (or let the app update itself, below).
To remove it, `brew uninstall --cask --zap matchday` also deletes Matchday's
settings, caches and notification memory.

## Updates

Matchday updates itself with [Sparkle](https://sparkle-project.org) from an
EdDSA-signed appcast published with each release. Right-click the ball and
choose **Check for Updates…**, or turn on automatic checks in **Settings**
(Updates). Automatic checking is off until you turn it on. Prereleases are never
offered.

Releases are cut by pushing a `v*` tag; see [RELEASING.md](RELEASING.md) for the
pipeline, the one-time setup and troubleshooting.

## Build and run

Requirements: macOS 15.6 or later, Xcode 26.

```sh
# Build
xcodebuild -project matchday.xcodeproj -scheme matchday -destination 'platform=macOS' build

# Unit tests
xcodebuild -project matchday.xcodeproj -scheme matchday -destination 'platform=macOS' \
  test -only-testing:matchdayTests
```

Or open `matchday.xcodeproj` in Xcode and run the `matchday` scheme; it builds
`Matchday.app`. The app is not sandboxed (so Sparkle can replace it in place) and
uses the hardened runtime. The first notification (or the **Test notification**
button) asks for notification permission.

Local data lives in `~/Library/`. Settings and notification memory from an
earlier sandboxed build are copied out of
`~/Library/Containers/com.juancasanueva.matchday/` once, on first launch:

| What | Where |
| --- | --- |
| Settings and followed teams | `Preferences/com.juancasanueva.matchday.plist` (UserDefaults) |
| HTTP cache | `Caches/com.juancasanueva.matchday/http` |
| Crest images | `Caches/com.juancasanueva.matchday/logos` |
| Notification memory | `Application Support/com.juancasanueva.matchday/notified.json` |

## Architecture

Screaming, hexagonal layout with container and presentational views:

```
matchday/
  App/          Composition root: MatchdayApp, AppDelegate and AppEnvironment
  Domain/       Pure models (Match, Team, League, Standings, AppSettings) and ports
  Application/  MatchdayStore (@Observable), MatchRepository (fetching, cache,
                tiered refresh), derivations for each tab, notification planner
  Data/         Adapters: ESPN client and mappers, HTTP and crest disk caches,
                UserDefaults settings, broadcasters, user notifications, login item
  Features/     One folder per screen (MenuBar, Panel, Following, Matches,
                Tables, Teams, Settings, About) plus Shared atoms (crest, chips, pills)
```

- Domain and derivation code is `nonisolated` and pure, so it is unit tested
  without the UI. Views read the store through containers and render plain
  values in presentational views.
- Ports (`SoccerDataSource`, `SettingsStore`, `NotificationSender`,
  `NotificationMemoryStore`, `HTTPTransport`) keep the network, disk and system
  services replaceable in tests.

## Tests

Swift Testing suites in `matchdayTests/`, with ESPN JSON fixtures in
`matchdayTests/Fixtures/`:

- ESPN decoding and normalization, client error handling.
- Refresh policy (hotness, TTLs, status), repository and HTTP cache.
- Settings persistence and migrations, launch at login.
- Where to watch, the Following, Matches and Tables derivations, the store.
- Notification rules (kickoff window, goals, own goals, full time, toggles,
  dedupe, 7-day pruning, no alerts for goals scored before launch).
- Crest cache (file names, `.missing` marker with 24-hour retry, shared
  downloads), panel keyboard commands, and color contrast fallbacks.
- About content (version and build from Info.plist, rows, links) and the
  status item context menu.
