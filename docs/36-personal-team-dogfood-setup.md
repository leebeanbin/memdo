# 36. Personal Team Dogfood Setup

> 이 문서는 브랜치/설치 절차만 다룬다. 3~4주 dogfooding 기간 동안 무엇을 확인하고 어떻게
> 기록할지는 [`37-founder-dogfooding-protocol.md`](./37-founder-dogfooding-protocol.md) 참고.

## Purpose

Install the current `main` codebase on a physical iPhone using free Xcode Personal Team
provisioning, **before** Apple Developer Program enrollment, so the founder can dogfood the app
daily for ~3-4 weeks. This is Phase 1 ("Personal Device Bring-up") of the reorganized v1.0 release
plan — see `docs/08-test-and-release-plan.md`.

## Why a branch, not a config/scheme

A clean `PersonalDogfood` Xcode configuration/scheme was investigated first. It is not achievable
without either duplicating the `Memdo` application target or introducing non-trivial custom build
logic, because:

- XcodeGen's `dependencies` embed (`embed: true` on `MemdoWidget`/`MemdoShare`) is a **target-level**
  setting with no per-configuration filter — there is no way to say "embed these extensions in
  Release but not in a Dogfood config" for the same target.
- The only way to avoid embedding them is to remove the dependency from the target entirely, which
  applies to every configuration built from that target (Debug, Release, and any custom config
  alike).

Given that constraint, this uses the documented fallback: a **separate git branch**
(`personal-team-dogfood`) carrying two temporary edits. `main` is never touched. Nothing here is
merged back to `main` — this branch exists only to be built and installed directly via Xcode, then
discarded (or periodically rebased on `main` to pick up new commits during the dogfood window) until
Phase 4 (Apple Developer Program enrollment).

## What is modified, and why

Both changes are marked `PERSONAL_TEAM_DOGFOOD` in place, with a pointer back to this doc.

1. **`apps/ios/Memdo/Memdo/Memdo.entitlements`** — `com.apple.security.application-groups`
   commented out (same pattern already used for `com.apple.developer.healthkit`). App Groups is not
   provisionable under a free personal-team signing identity; leaving it declared would make the
   `Memdo` target's own provisioning profile fail to validate, blocking the build entirely.
2. **`apps/ios/Memdo/project.yml`** — the `MemdoWidget: embed: true` / `MemdoShare: embed: true`
   dependency entries under the `Memdo` target are commented out. Both extension targets carry the
   same App Groups entitlement; leaving them embedded would carry the same provisioning failure into
   the main app's build even though `Memdo.entitlements` itself is fixed.

**No source file inside `MemdoWidget/` or `MemdoShare/` is touched.** Their entitlements, code, and
production design are unchanged — they are simply not part of this branch's build output.

## What this means for app behavior during dogfooding

Traced against actual call sites (not assumed) before making this change:

- Every place the main app touches the shared App Group container
  (`ScheduleModel.swift`, `SettingsView.swift`, `MemdoGuideSheet.swift`, `WallpaperIntent.swift`,
  `WallpaperPreviewSheet.swift`, `PendingWorkoutStore.swift`) goes through
  `UserDefaults(suiteName:)` via optional chaining or `@AppStorage(store:)`, never force-unwrapped.
  With the entitlement absent, `UserDefaults(suiteName:)` returns `nil` at runtime (not a crash);
  writes become no-ops, reads fall back to `nil`/`false`/`UserDefaults.standard`. **No crash risk.**
- No code in `Memdo/*.swift` has a startup or runtime dependency on the Share extension's binary
  being present — `PendingWorkoutStore`'s foreground drain simply finds an empty queue.
- `MemdoLiveActivity.swift` is compiled into the `MemdoWidget` target (per `project.yml` sources),
  so excluding Widget also excludes Live Activities from this build.
- Google/GitHub OAuth is unaffected: the redirect is the custom URL scheme `memdo://auth/callback`
  (`supabase/config.toml`), not tied to Bundle ID, Associated Domains, or App Groups. Bundle ID
  (`com.memdo.ios`) does not change on this branch.

Practical effect: the widget shows no live data (not embedded at all), "Share to Memdo" isn't
available in the Share Sheet, Live Activities don't run, HealthKit stays disabled (unchanged from
`main`). Everything else — core app, local notifications incl. the 7-day/48-cap reconciliation,
Google/GitHub sign-in, offline sync, Agent/BYOK, deep links, MetricKit — is unaffected.

## Revert checklist (hard gate before Phase 5 Release/Archive)

This branch must never be the source of a Release/Archive/TestFlight build. Before Phase 5:

- [ ] Confirm the Release build comes from `main` (or a branch cut from `main`), not
      `personal-team-dogfood`.
- [ ] Confirm `Memdo.entitlements` on that branch has `com.apple.security.application-groups`
      **active** (uncommented).
- [ ] Confirm `project.yml` on that branch has `MemdoWidget`/`MemdoShare` `embed: true`
      **uncommented** under the `Memdo` target's dependencies.
- [ ] `xcodegen generate` + Archive build succeeds with Widget and Share both present.
- [ ] Grep for `PERSONAL_TEAM_DOGFOOD` across the release branch — zero matches expected.

## First-device-install procedure

1. On the iPhone: Settings → Privacy & Security → Developer Mode → enable → restart → confirm.
2. Connect the iPhone to the Mac (cable, or wireless debugging after one cabled pairing).
3. Xcode → Settings → Accounts → confirm the free Apple ID is signed in.
4. `git checkout personal-team-dogfood && xcodegen generate` → open `Memdo.xcodeproj`.
5. Select the `Memdo` scheme, select the physical iPhone as the run destination.
6. Memdo target → Signing & Capabilities → "Automatically manage signing" checked → Team = personal
   team. (Widget/Share targets are not part of this build, so their signing doesn't need touching.)
7. Build & Run (⌘R).
8. First launch: iOS blocks it as "Untrusted Developer" → Settings → General → VPN & Device
   Management → trust the certificate → relaunch from the Home Screen.
9. **Weekly**: personal-team provisioning profiles expire 7 days after issuance — reconnect and
   re-run from Xcode at least once a week during the dogfood window, or the installed app stops
   launching.
