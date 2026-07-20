# Why Did I Unlock

> Working name — the public/store brand is not finalized. Android-first digital-wellbeing app, built with **Flutter**.

## What it is

On every phone unlock, a prompt asks **"What are you unlocking for?"** You declare an intent (a preset or custom text), and it persists as a **floating bubble** across all apps until you dismiss it — a constant, gentle reminder of *why* you picked up your phone. An optional countdown timer is planned. The defensible idea is the **bubble + timer** accountability loop, not the unlock prompt alone.

## Status (2026-07-20)

- **v0.3.0 shipped** (tagged), verified on a real device: unlock/lock detection, intent-capture screen (presets + custom text), the bubble showing the declared intent, manual dismiss, and debug logging.
- **Post-v0.3.0 reliability fixes merged to `main`** (not yet tagged): the monitoring now survives the app being swiped from Recents (persistent background engine), restarts after reboot, and the capture screen covers the full display.
- **Not built yet:** local intent-history storage + smart cooldown (the next sprint, designed), timer, voice input, dashboard, onboarding.

This is a work-in-progress shared informally with friends via sideloaded APK — not on the Play Store.

## Documentation map

| Doc | What it's for |
|---|---|
| **[`CLAUDE.md`](CLAUDE.md)** | The authoritative operational context & decision log. **Read this first** if you're picking up development. Covers current state, working rules, engineering principles, open decisions. |
| **[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)** | System design — the three-Flutter-engine topology, native components, event flows, and plugin gotchas. Read before touching native/overlay code. |
| **[`docs/PRD.md`](docs/PRD.md)** | Current product requirements (Flutter-accurate). |
| **[`docs/SETUP.md`](docs/SETUP.md)** | Windows dev-environment bring-up (toolchain, device). |
| `docs/archive/` | Superseded historical docs (e.g. the original RN/Expo v1.0 PRD) — reference only, not current. |

> If two docs ever disagree, `CLAUDE.md` is the most current and wins.

## Quick start (development)

Full detail in [`docs/SETUP.md`](docs/SETUP.md). In short: install a current stable Flutter (Dart SDK ≥ 3.11.5), connect a **physical** Android device (emulators don't reproduce unlock/overlay behavior), then:

```
flutter pub get
flutter run --release        # physical device only
```

Release build for sharing: `flutter build apk --release --split-per-abi` (send the `arm64-v8a` APK). Note: release signing needs `android/key.properties` + the keystore, which are gitignored and not in this repo — a fresh clone builds fine but falls back to debug signing. See `CLAUDE.md` §5.
