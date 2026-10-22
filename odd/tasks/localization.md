# Localization

Branch `feat/localization` from `main` d778eb7. Delivery: single feature branch with
work-unit commits, merged to `main` when the user approves (the user's recent flow).

## Objective

Translate Matchday into English, Spanish, French, German, Italian, Portuguese
(Portugal), Japanese, Korean and Simplified Chinese, and add a language selector
in Settings that switches the app language at runtime, modeled on the `rgb`
project's selector.

## Why

The user added nine flag assets and `Localizable.xcstrings` and wants the app in
those languages. Today almost nothing is localized: custom views take `String`,
and most visible text is built as `String` in `matchday/Application/` derivations.

## Scope and constraints

- Languages (raw values double as `.lproj` names): `en, es, fr, de, it, pt-PT, ja, ko, zh-Hans`.
  Flags: `UK, Spain, France, Germany, Italy, Portugal, Japan, South-korea, China`.
- Like `rgb`: no "System" chip; until the user picks one (`nil`), follow the system
  language (match on language code, `pt` → pt-PT, `zh` → zh-Hans, unknown → en).
  Native names are never translated. Switching applies instantly, no relaunch.
- Runtime switching: `.environment(\.locale, …)` on both SwiftUI roots (panel
  popover, About window) plus a language bundle for strings built outside views
  (derivations, notifications, NSMenu, tooltips, About window title).
- Data from ESPN (team names, league names, zone descriptions, status details) and
  broadcaster names stay as delivered.
- Tests keep running in English (explicit `en` language/locale where they assert text).
- Translations are machine-authored by the agent; football terminology per language.

## Tasks

- [x] T0 Commit the user's flag assets and string catalog — 817a119.
- [x] T1 Language model and selector: `AppLanguage`, `AppSettings.language`
      (backward-compatible decode), store wiring, runtime bundle/locale applied to the
      panel and About roots, flag grid in Settings. Tests first.
      Evidence: RED (missing symbols) then GREEN, unit suite and Release build pass;
      commit `feat(l10n): add the app language setting and flag selector`. T2 API:
      `String(appLocalized:)` / `String(appLocalizedKey:)` over `AppLocalization.shared`
      (matchday/Localization/AppLocalization.swift); SwiftUI roots wrap `AppLocaleRoot`.
- [x] T2 Make every user-visible string localizable: custom views take
      `LocalizedStringKey`/resources, derivations/notifications/menu/tooltips resolve
      through the language bundle, dates follow the selected locale, fix the
      "Click a %@" sentence. English tests stay green.
      Also (accepted T1 review advisories): retitle an open About window when the
      language changes; fall back to the development language (`en`) instead of the
      system-resolved base bundle when a language has no `.lproj`; remove the temp
      bundles `AppLocalizationTests` creates.
      Also (accepted review finding): the app locale keeps the system region when the
      language differs (`en_NL` on a Dutch Mac, `de_NL` for German chosen there), so
      24-hour time and date conventions survive; `pt-PT`/`zh-Hans` keep their own
      locale (a `pt_BR`/`zh_TW` locale would point SwiftUI at an uncarried copy).
      Suggestion done: `LanguageObserver` (extracted from the status item) applies the
      bundle only on an actual language/locale change, with tests.
      Evidence: RED (missing symbols) then GREEN; unit suite and Release build pass;
      commit 46afd81. Design: views use literal keys, `Chip`/`SectionHeader` have
      `verbatim:` inits for data; model labels (About rows, appearance, watch label,
      tab names) stay English catalog keys looked up by the view with
      `LocalizedStringKey(_:)` (`extractionState: manual`); derivations resolve through
      `DisplayContext.bundle` (the store's language bundle); view-built strings use
      `Locale.appBundle` from `\.locale`. English output change: short dates are now
      locale-ordered (`Fri, Oct 23` instead of `Fri Oct 23`). Catalog: 161 keys,
      synced from compiler `.stringsdata` with `xcstringstool sync`.
- [ ] T3 Translate the catalog into the 8 languages; add catalog tests (every key
      translated in every language, matching format arguments, `.lproj` present);
      README mention.
      Also (accepted T2 review, approved + acknowledged review-94da83cb5ab2e5aa):
      footnote country precedence in WhereToWatch (the catalog name must win over a
      raw-code fallback; test the US/unknown branches); replace the fixed `Task.yield`
      loops in LanguageObserver/About retitle tests with a deadline-based wait.

## Acceptance criteria

- Picking a flag switches all app text (panel, About, context menu, tooltip, new
  notifications) without relaunch and survives relaunch.
- Every catalog key is translated into all 9 languages; catalog tests pass.
- Full unit suite green; Release build launches.

## Progress

| Task | Route | Evidence |
|---|---|---|
| T0 | inline (mechanical commit) | 817a119 |
| T1 | delegated writer (2+ non-trivial files) | 677c6bf; 19 new test functions; `xcodebuild test -only-testing:matchdayTests` TEST SUCCEEDED (parent spot check re-ran: SUCCEEDED); Release BUILD SUCCEEDED; ~600 changed lines (new files + tests, not split). Review: medium, granted, approved + acknowledged (review-fa8268616a4ce637); advisories folded into T2 |
| T2 | delegated writer (2+ non-trivial files, ~1.1k changed lines incl. catalog; not split: views, derivations and catalog move together) | 46afd81; new tests: LocalizedTextTests (derivation + notification through a ja bundle, catalog keys/comments, About retitle, Chip verbatim), LanguageObserverTests, en fallback, region carry, locale ordinals/dates; `xcodebuild test -only-testing:matchdayTests` TEST SUCCEEDED; Release BUILD SUCCEEDED |

## Next step

T3: translate the 161 catalog keys into the 8 languages and extend `LocalizedTextTests`
with per-language completeness and format-argument checks.
