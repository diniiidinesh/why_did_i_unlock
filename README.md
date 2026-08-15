# Beacon

> Play title: **Beacon: Mindful Phone Use**. Code package remains `why_did_i_unlock`. Android-first digital-wellbeing app, built with **Flutter**.

## What it is

On every phone unlock, a prompt asks **"What are you unlocking for?"** You declare an intent (a preset or custom text), and it persists as a **floating bubble** across all apps until you dismiss it — a constant, gentle reminder of *why* you picked up your phone. An optional countdown timer is planned. The defensible idea is the **bubble + timer** accountability loop, not the unlock prompt alone.

## Status (2026-08-16)

- **v0.3.0 shipped** (tagged 2026-07-17), verified on a real device: unlock/lock detection, intent-capture screen (presets + custom text), the bubble showing the declared intent, manual dismiss, and debug logging.
- **v0.3.x** (reliability fixes merged to `main`, tagged `v0.3.1`): monitoring survives app-swipe-out, restarts after reboot, full-display capture screen.
- **v0.4.0 / v0.4.1 shipped** (merged to `main`, PRs #5/#6): meaningful presets, OK button, "Just Like That" honest-no-intent option, master prompt on/off toggle, direct-boot auto-restart, capture-screen thumb-zone layout.
- **v0.5.0 shipped** (Sprint 3, merged to `main`): local intent-history storage (`sqflite`), cooldown+probability prompt triage, a minimal history view.
- **v0.6.0 shipped** (Sprint 4 Stage A, merged to `main` 2026-07-24): 5-step onboarding, Settings/Status & troubleshooting/About/Manage-options screens, schema v2 (`unlock_log`, declare/dismiss lifecycle, presets as a real table), windowed insight queries, close-capture-on-lock, a one-tap battery-optimization-exemption dialog, `minSdk`/`targetSdk` pinned to 29/36 for Play submission.
- **v0.6.1 shipped — Beacon rebrand + Stage B** (merged to `main` 2026-07-27, PRs #8/#9, `0.6.1+9`): T17 CSV export, T18 Home insight cards + Your data, hybrid chat-head bubble (Done/Snooze, edge-snap, native orientation reopen), store brand **Beacon** (Play title `Beacon: Mindful Phone Use`, listing docs in `docs/PLAY_SUBMISSION.md`), Beacon amber UI tokens, branding assets/splash/FGS icon, Report a problem, prompt default **100%** with explained 1-min cooldown, verb default presets (Check mail / Message someone / Book a cab / Order food / Pay someone), Home mean row + pull-to-retry load fix, OEM autostart UX (manufacturer highlight + Home nudge) + overlay find-hint. Privacy live at `https://dineshkaliki.com/beacon/privacy/`.
- **v0.6.2 shipped** (merged to `main` 2026-07-30, PR #14, `0.6.2+10`): tablet/Chromebook/Wear OS excluded from Play's compatible-devices list (`android.hardware.touchscreen` required), overlay snooze `debugPrint` gated behind `kDebugMode` (was logging declared-intent text in release builds).
- **v0.6.2 fixes** (merged to `main` 2026-08-11, PR #15): "Report a problem" cross-isolate logging bug (stale/clobbered reads across isolates) + mailto `+`-encoding bug, both fixed; a real native crash surfaced by Android vitals (`flutter_overlay_window`'s `OverlayService` `NullPointerException` on Android's post-low-memory-kill service restart, hit 3 testers) fixed via a forked/patched plugin. Both confirmed on-device.
- **v0.6.3** (`0.6.3+13`, merged to `main` through PR #17): two "unlock stopped prompting" bugs in the overlay lifecycle — a `showOverlay()` reopen call site missing its timeout guard, then a `closeOverlay()` hang leaving the active-overlay flag stuck true — both fixed with the timeout-guard pattern plus an `_abandonLostBubble()` recovery path that fails open. Also adds a breadcrumb trail (`ProblemReportLog.recordBreadcrumb`) so a problem report shows what *led up to* a failure, not just a caught exception. See `CLAUDE.md` §2 for the full account.
- **Not built yet:** timer/countdown (next big product wedge), voice input.

**Not yet live to the public — in Play review.** The 14-continuous-day / 12-opted-in closed-test gate cleared on schedule (29 testers invited — Friends 21 + Testers List 8), **production access was granted 2026-08-13**, and `0.6.3 (11)` was submitted the same day. It is awaiting review for that first public release as of 2026-08-16. See `docs/PLAY_SUBMISSION.md` §4. On-device QA matrix (`docs/TEST_PLAN.md` 54–76) still open.

**In flight (2026-08-16):** the **onboarding revamp** is four PRs in [`docs/erd/onboarding-revamp-2026-08-15.md`](docs/erd/onboarding-revamp-2026-08-15.md). **PR 1 merged** (copy diet + `OnboardingStep` enum, verified on-device). Next is the animated walkthrough. Priority order across all open work — including two P0s that are *not* onboarding (the outstanding-intent prompt, and a bubble-salience regression reported independently by two testers) — is in [`docs/BACKLOG.md`](docs/BACKLOG.md)'s `CURRENT PRIORITY ORDER` block.

## Documentation map

| Doc | What it's for |
|---|---|
| **[`CLAUDE.md`](CLAUDE.md)** | The authoritative operational context & decision log. **Read this first** if you're picking up development. Covers current state, working rules, engineering principles, open decisions. |
| **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** | System design — the three-Flutter-engine topology, native components, event flows, and plugin gotchas. Read before touching native/overlay code. |
| **[`docs/DATA_MODEL.md`](docs/DATA_MODEL.md)** | The on-device schema (ERD), its invariants, and the reasoning behind them. Read before touching `lib/intent_store.dart` or any write path in `lib/main.dart`. |
| **[`docs/PRD.md`](docs/PRD.md)** | Current product requirements (Flutter-accurate). |
| **[`docs/BACKLOG.md`](docs/BACKLOG.md)** | Deferred features/fixes/ideas with priorities. Strategic decisions live in `CLAUDE.md` §11/§12. |
| **[`docs/TEST_PLAN.md`](docs/TEST_PLAN.md)** | Living test tracker — automated suites + the manual on-device matrix (unlock/overlay/reboot behaviour). |
| **[`docs/USER_INTERVIEWS.md`](docs/USER_INTERVIEWS.md)** | Running list of questions to ask testers/friends in 1:1s, tied to open product decisions. |
| **[`docs/SETUP.md`](docs/SETUP.md)** | Windows dev-environment bring-up (toolchain, device). |
| **[`docs/PLAY_SUBMISSION.md`](docs/PLAY_SUBMISSION.md)** | Google Play listing & review prep — special-use foreground service justification, Data Safety answers, closed-testing requirement, submission gates. |
| **[`docs/PRIVACY_POLICY.md`](docs/PRIVACY_POLICY.md)** | The app's privacy policy — drafted for the Play listing, honest about zero network calls/local-only storage. |
| **[`docs/DOC_UPKEEP.md`](docs/DOC_UPKEEP.md)** | For Claude Code: how to keep these docs current without burning context. |
| `docs/erd/` | Archived sprint planning documents (ERDs, screen maps, task breakdowns), one dated file per sprint (incl. `bubble-ux-hybrid-plan-2026-07-24.md`, `beacon-visual-identity-2026-07-24.md`, `verb-presets-job-goers-2026-07-25.md`). May be updated as implementation proceeds — see each file's "Update log"; a new sprint still gets its own new file. See `docs/DATA_MODEL.md` for the current-state schema instead of re-deriving it from a plan. |
| `docs/debug/` | Dated, git-tracked session logs and RCAs from real debugging investigations (e.g. Sprint 3 storage bugs; post-reboot overlay stall / empty presets RCA 2026-07-24) — the durable "how we actually found this" record behind a fix, referenced from `CLAUDE.md`/`ARCHITECTURE.md`/`BACKLOG.md` where relevant. |
| `docs/archive/` | Superseded historical docs (e.g. the original RN/Expo v1.0 PRD) — reference only, not current. |

> If two docs ever disagree, `CLAUDE.md` is the most current and wins.

## Quick start (development)

Full detail in [`docs/SETUP.md`](docs/SETUP.md). In short: install a current stable Flutter (Dart SDK ≥ 3.11.5), connect a **physical** Android device (emulators don't reproduce unlock/overlay behavior), then:

```
flutter pub get
flutter run --release        # physical device only
```

Release build for sharing: `flutter build apk --release --split-per-abi` (send the `arm64-v8a` APK). Note: release signing needs `android/key.properties` + the keystore, which are gitignored and not in this repo — a fresh clone builds fine but falls back to debug signing. See `CLAUDE.md` §5.
