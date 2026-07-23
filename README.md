# Why Did I Unlock

> Working name — the public/store brand is not finalized. Android-first digital-wellbeing app, built with **Flutter**.

## What it is

On every phone unlock, a prompt asks **"What are you unlocking for?"** You declare an intent (a preset or custom text), and it persists as a **floating bubble** across all apps until you dismiss it — a constant, gentle reminder of *why* you picked up your phone. An optional countdown timer is planned. The defensible idea is the **bubble + timer** accountability loop, not the unlock prompt alone.

## Status (2026-07-24)

- **v0.3.0 shipped** (tagged 2026-07-17), verified on a real device: unlock/lock detection, intent-capture screen (presets + custom text), the bubble showing the declared intent, manual dismiss, and debug logging.
- **v0.3.x** (reliability fixes merged to `main`, tagged `v0.3.1`): monitoring survives app-swipe-out, restarts after reboot, full-display capture screen.
- **v0.4.0 / v0.4.1 shipped** (merged to `main`, PRs #5/#6): meaningful presets, OK button, "Just Like That" honest-no-intent option, master prompt on/off toggle, direct-boot auto-restart, capture-screen thumb-zone layout.
- **v0.5.0 shipped** (Sprint 3, merged to `main`): local intent-history storage (`sqflite`), cooldown+probability prompt triage, a minimal history view.
- **v0.6.0 shipped** (Sprint 4 app shell, merged to `main` 2026-07-24): 5-step onboarding, Settings/Status & troubleshooting/About/Manage-options screens, schema v2 (`unlock_log`, declare/dismiss lifecycle, presets as a real table), windowed insight queries, close-capture-on-lock, a one-tap battery-optimization-exemption dialog, `minSdk`/`targetSdk` pinned to 29/36 for Play submission. Two known bugs found during integration are tracked in `docs/BACKLOG.md` (stale overlay preset cache until reboot; a manual test trigger arming real cooldown) — see that file before touching triage or the config relay.
- **Not built yet:** timer/countdown (the actual bubble+timer differentiator, next priority), voice input, CSV export (T17), Home insight cards (T18), the two known bugs above, a store listing (brand name still unresolved — `CLAUDE.md` §12).

This is a work-in-progress shared informally with friends via sideloaded APK — not on the Play Store.

## Documentation map

| Doc | What it's for |
|---|---|
| **[`CLAUDE.md`](CLAUDE.md)** | The authoritative operational context & decision log. **Read this first** if you're picking up development. Covers current state, working rules, engineering principles, open decisions. |
| **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** | System design — the three-Flutter-engine topology, native components, event flows, and plugin gotchas. Read before touching native/overlay code. |
| **[`docs/DATA_MODEL.md`](docs/DATA_MODEL.md)** | The on-device schema (ERD), its invariants, and the reasoning behind them. Read before touching `lib/intent_store.dart` or any write path in `lib/main.dart`. |
| **[`docs/PRD.md`](docs/PRD.md)** | Current product requirements (Flutter-accurate). |
| **[`docs/BACKLOG.md`](docs/BACKLOG.md)** | Deferred features/fixes/ideas with priorities. Strategic decisions live in `CLAUDE.md` §11/§12. |
| **[`docs/TEST_PLAN.md`](docs/TEST_PLAN.md)** | Living test tracker — automated suites + the manual on-device matrix (unlock/overlay/reboot behaviour). |
| **[`docs/SETUP.md`](docs/SETUP.md)** | Windows dev-environment bring-up (toolchain, device). |
| **[`docs/PLAY_SUBMISSION.md`](docs/PLAY_SUBMISSION.md)** | Google Play listing & review prep — special-use foreground service justification, Data Safety answers, closed-testing requirement, submission gates. |
| **[`docs/PRIVACY_POLICY.md`](docs/PRIVACY_POLICY.md)** | The app's privacy policy — drafted for the Play listing, honest about zero network calls/local-only storage. |
| **[`docs/DOC_UPKEEP.md`](docs/DOC_UPKEEP.md)** | For Claude Code: how to keep these docs current without burning context. |
| `docs/erd/` | Archived sprint planning documents (ERDs, screen maps, task breakdowns), one dated file per sprint. May be updated as implementation proceeds — see each file's "Update log"; a new sprint still gets its own new file. See `docs/DATA_MODEL.md` for the current-state schema instead of re-deriving it from a plan. |
| `docs/debug/` | Dated, git-tracked session logs from real debugging investigations (e.g. the Sprint 3 storage bugs) — the durable "how we actually found this" record behind a fix, referenced from `CLAUDE.md`/`ARCHITECTURE.md` where relevant. |
| `docs/archive/` | Superseded historical docs (e.g. the original RN/Expo v1.0 PRD) — reference only, not current. |

> If two docs ever disagree, `CLAUDE.md` is the most current and wins.

## Quick start (development)

Full detail in [`docs/SETUP.md`](docs/SETUP.md). In short: install a current stable Flutter (Dart SDK ≥ 3.11.5), connect a **physical** Android device (emulators don't reproduce unlock/overlay behavior), then:

```
flutter pub get
flutter run --release        # physical device only
```

Release build for sharing: `flutter build apk --release --split-per-abi` (send the `arm64-v8a` APK). Note: release signing needs `android/key.properties` + the keystore, which are gitignored and not in this repo — a fresh clone builds fine but falls back to debug signing. See `CLAUDE.md` §5.
