# CLAUDE.md — Why Did I Unlock

> Operational context for Claude Code. Read this fully at the start of every session.
> Last updated: 2026-07-21 (rev 6 — v0.4.1 shipping: capture-screen thumb-zone layout revamp, "Just Like That" pill styling. v0.4.0 shipped 2026-07-21: prompt on/off toggle, meaningful presets, "Just Like That", OK button, direct-boot restart; `shared_preferences` added. Sprint 3 storage+cooldown still not built). Owner: Dinesh.
> Working name: **Why Did I Unlock** (originally "IntentLock" in the PRD). The public/store brand is NOT finalized — see §12.
> New here? Start with `README.md` (front door + doc map). Authoritative docs: this file (operational context), `docs/ARCHITECTURE.md` (system design), `docs/PRD.md` (product).
> **This file — not Claude Code's local memory — is the durable source of truth across machines.** Claude Code's auto-memory (`~/.claude/projects/.../memory/`) is local-filesystem-only with no cross-device sync; anything that needs to survive a machine switch belongs here or elsewhere in the repo, not only in memory.

## 1. What this app is

Why Did I Unlock (working name) is an Android-first digital-wellbeing app. Core loop:

1. **Intent capture** — on phone unlock, a prompt asks "What are you unlocking for?" (presets / voice / custom text).
2. **Floating bubble** — the declared intent persists as a draggable overlay bubble across all apps until the user completes it.
3. **Optional timer** — a countdown can be attached; the bubble changes color / pulses as time runs out.

The defensible combination is **bubble + timer**, NOT the unlock prompt on its own (see §10). Positioning is deliberately drifting from "unlock interceptor" toward "phone session manager."

> **Post-v0.3.0 note (merged to `main` 2026-07-20, merge commit `e7873a5`, tagged `v0.3.1`):** unlock handling moved off `MainActivity` into a **persistent background Flutter engine** so it survives the app being swiped from Recents (was a P0); boot auto-restart (`BootReceiver`); full-screen capture-window sizing/gravity fixes. Three-engine topology is in **`docs/ARCHITECTURE.md`** — read before touching native/overlay. The §2 "→ `MainActivity` → `MethodChannel`" line below is the older v0.3.0 shape, superseded by that doc.
> **v0.4.0 note (merged to `main` 2026-07-21, PR #5, version `0.4.0+5`):** shipped — meaningful presets (Payments/Calls/Messages/Food Order/Commute), an on-screen OK button, a "Just Like That" honest-no-intent option (logs, no bubble), a **master prompt on/off toggle** (`HomeScreen` switch → `shared_preferences` → single `_shouldPrompt()` gate in the background engine, the seam where future scheduling plugs in), and **direct-boot restart** (`LOCKED_BOOT_COMPLETED` + `directBootAware`, so monitoring is up before the first post-reboot unlock — verified). New dep: `shared_preferences` (federated → needs Windows Developer Mode to build, as `sqflite` will too). The interim keyboard-avoidance fix just shifted content up (janky), and "Just Like That" was a bare `TextButton`.
> **v0.4.1 note (PR #6, pending merge, version `0.4.1+6`):** Polish pass on the capture screen — proper thumb-zone layout revamp (title/presets/"Just Like That"/text field all bottom-anchored to the one-handed reachable zone; text field pinned as footer just above keyboard, so keyboard no longer shoves content off-screen), and "Just Like That" is now a real outlined pill instead of bare italic text. Also syncs `macos/Flutter/GeneratedPluginRegistrant.swift` (had drifted since v0.4.0). Pending friend-testing feedback before merge to `main`.

## 2. Current state — ground truth (the PRD is partly stale)

- **Stack is Flutter.** The PRD (in the repo / Drive) still describes React Native + Expo + Replit. That is obsolete. Trust THIS file over the PRD on anything stack-, pricing-, or platform-related. Flutter was chosen over RN/Expo after a feature-by-feature comparison, mainly because `flutter_overlay_window` handles the overlay + permission complexity cleanly.
- **v0.3.0 shipped and merged to `main`, tagged on GitHub (2026-07-17).** Confirmed on a real device, release build. Sprint 1 delivered the plumbing: unlock detection (`UnlockReceiver` → `UnlockListenerService` foreground service → `MainActivity` → Flutter `MethodChannel`) triggers a floating overlay via `flutter_overlay_window`. Sprint 2 delivered the actual product on top of it:
  - Intent-capture screen appears on unlock (preset/custom text).
  - **The bubble displays the actual declared intent text**, as a readable pill (not a tiny circle — the plugin's `showOverlay()` sizes in raw device pixels, not dp, see §5).
  - Bubble persists across app switches. **One confirmed OS-level exception: the bubble does not render over the Settings app** — expected Android anti-tapjacking behavior since Android 12, not a bug.
  - Tapping the bubble's × badge dismisses it (no completed-vs-abandoned distinction yet — only one dismiss gesture exists).
  - **Confirmed single-active-intent behavior (intentional):** if the phone is unlocked again while an intent is still incomplete, the existing bubble persists as-is and a fresh capture screen is NOT re-triggered. A new capture screen only appears once the current intent is dismissed. Any cooldown/triage logic (§3, §9) must compose with this, not fight it.
  - Foreground service survived a background-kill test on a Realme/ColorOS device after a manual app reopen — **battery-optimization exemption / autostart toggle (OEM reliability hardening) is still NOT done** and should happen before treating background survival as production-reliable over hours, not just a short test session.
  - **v0.3.0 additions on top of Sprint 2:** screen-lock detection (`ACTION_SCREEN_OFF`, symmetric to the existing unlock path) and debugPrint logging of every intent declared/dismissed (text, source [preset/custom], timestamps, duration) — this logging is NOT persisted anywhere yet, purely for visibility during development.
  - Still not built: voice input, timer, local storage/history, dashboard, completed-vs-abandoned distinction.
- Overlay is handled by the **`flutter_overlay_window`** package (currently `^0.5.0`).
- Target: **Q3 2026 MVP**, built incrementally, sprint by sprint.
- The PRD has been rewritten for Flutter as `docs/PRD.md` (the original v1.0 is archived at `docs/archive/IntentLock_PRD_v1_original.md`, kept for reference but stale on stack/pricing).
- **Code package name (confirmed from `pubspec.yaml`): `why_did_i_unlock`.** Matches the working name; no code rename needed.
- **Dependencies as of v0.4.0:** `flutter_overlay_window`, `cupertino_icons`, **`shared_preferences`** (runtime — added v0.4.0 for the prompt toggle; federated plugin, so building needs **Windows Developer Mode** enabled, same requirement `sqflite` will bring in Sprint 3); `flutter_launcher_icons` (dev-only). No `sqflite`/state-management yet — `sqflite` lands with Sprint 3 (§3). `pubspec.yaml` `version` is `0.4.0+5` (was `0.3.1+4`).
- **Toolchain floor:** pubspec requires Dart SDK `^3.11.5`, so install a **current stable Flutter** on the new machine. If `flutter pub get` fails with an SDK-constraint error, the Flutter version is too old — run `flutter upgrade`.
- **Manifest reality check:** `RECORD_AUDIO` / `POST_NOTIFICATIONS` are NOT yet in `AndroidManifest.xml` (voice/timer not built). The manifest DOES include `FOREGROUND_SERVICE_SPECIAL_USE` (Android 14+ requirement) — the PRD never mentions this permission; it's a real addition, not a gap. **`android:allowBackup` is not explicitly set** (defaults to `true`) — flagged in a security review as needing to become `false` before/alongside local storage landing, since default Android app-data backup would otherwise sweep up intent history, conflicting with the local-first/privacy stance (§11).

## 3. Sprint 3 — design decided, feature work NOT yet built

The real P0 scope for Sprint 3 — local intent-history storage and cooldown/smart-triage — has been fully designed but not implemented as of v0.3.0. Decisions below are ready to build against whenever this is picked back up:

- **Storage: `sqflite`.** One table `intent_log` (`id`, `text`, `source` [`preset`/`custom`], `declared_at`, `completed_at`, both ms-epoch). One row written per completed intent, at dismissal — no in-progress-row tracking, since incomplete intents aren't tracked yet.
- **Critical architecture constraint, verified against the plugin's native source:** the overlay's Flutter engine (the second engine `flutter_overlay_window` spins up) has **no plugins registered on it** other than the overlay plugin's own channel — neither `FlutterOverlayWindowPlugin.java` nor `OverlayService.java` ever calls `GeneratedPluginRegistrant.registerWith(...)` for that engine. This means **`sqflite` (or any other plugin) cannot be called directly from `OverlayRoot`/`overlayMain()` code** (e.g. inside `_dismissBubble()` in `lib/main.dart`) — it would throw `MissingPluginException` at runtime. The plan: on dismiss, the overlay isolate hands the completed-intent record to the **main app isolate** via `FlutterOverlayWindow.shareData()` / `overlayListener` (the plugin's existing overlay↔main-app message channel), and the main isolate — which has normal plugin registration via standard `FlutterActivity` — performs the actual `sqflite` write. Known gap this doesn't solve: if the main app process is killed by the OS (aggressive OEM battery management) between dismiss and write, that record is lost — not a new problem, same class as the existing OEM-reliability gap above.
- **Cooldown:** no separate timestamp store needed — query `MAX(completed_at)` from `intent_log` itself. Checked in `_showCaptureScreen()` (main isolate, where the DB lives) alongside the existing `isActive()` guard, before calling `showOverlay()` again. **Default: 1 minute**, a hardcoded named constant (mirrors how `intentMaxInputLength` was made a constant) — not yet user-configurable. Eventual plan (not this sprint): a Settings screen offering presets (5/10/15 min + custom), mirroring the existing intent-preset UI pattern; same eventual treatment planned for the timer duration once that feature exists (see §4).
- Every dismiss currently logs as one undifferentiated status, since only one dismiss gesture (the × badge) exists — no completed-vs-abandoned distinction in the UI yet. Don't assume the schema needs a status field beyond that until the UI actually supports the distinction.

## 4. Bubble UX backlog — deferred, not built (Dinesh's feedback on the Sprint 2 pill)

None of these are scoped for any specific sprint yet — parked for a future polish pass once the Sprint 3 core (storage/cooldown) lands:

- **Drag/edge-snap behavior:** the bubble can currently be dragged to extreme screen edges, even partly off-screen. Consider Messenger-style edge-snap (`positionGravity` in `flutter_overlay_window` already supports `left`/`right`/`auto`) and/or guaranteeing the × stays reachable regardless of drag position.
- **Adaptive bubble sizing:** width should adapt to the intent text up to a max char/size limit before truncating, and consider a smaller-but-still-legible font so more fits. Currently a fixed 200×56dp pill, single line, 14sp, truncates with ellipsis.
- **Smaller footprint + richer actions:** shrink the bubble's on-screen footprint while still delivering value; consider replacing the single × with separate **Done** and **Snooze** actions instead.
- **The icon+expand hybrid Dinesh wants evaluated eventually:** each declared intent gets its own icon; the collapsed bubble shows just the icon, and tapping expands it to reveal the full text — closer to the Messenger/Messages chat-head pattern. The readable pill was chosen for Sprint 2 as the simpler build; this hybrid is a later evaluation, not a commitment either way.

## 5. Distribution & signing (for sharing test builds with friends)

- **v0.3.0 is signed with a real release keystore**, replacing the earlier debug-signed builds: `android/app/keystore/upload-keystore.jks`, alias `upload`. **Both the keystore and `android/key.properties` are gitignored and must never be committed** — the password is kept only in Dinesh's password manager, not in this repo or any doc. If the keystore or its password is ever lost, no future build can be signed to match it — anyone with an existing install would need a full uninstall/reinstall to get any update. `build.gradle.kts`'s release `signingConfig` falls back to debug signing automatically if `key.properties` is absent, so a fresh clone without the keystore still builds (debug-signed).
- **Sharing method:** no Play Store listing exists (store brand still unresolved, §12) — sideload the `arm64-v8a` split APK directly (`flutter build apk --release --split-per-abi`; `arm64-v8a` covers essentially all phones from the last ~7+ years).
- **Known friend-onboarding snag, not an app bug:** Android 13+'s "Restricted Settings" blocks the overlay permission ("Display over other apps") on the *first* grant attempt for any sideloaded app — a deliberate OS anti-malware measure, since overlay permission + sideloading is a common phishing pattern, and it can't be worked around from inside the app. Fix, once per install: **App info → ⋮ menu → "Allow restricted settings" → confirm → then grant the permission normally.** Worth telling people this upfront rather than letting them hit the confusing "App was denied access" dialog cold.
- **Security review conclusion (2026-07-17):** no exploitable vulnerabilities found in current code — no exported components beyond the required launcher activity, the lock/unlock receiver relies on protected system broadcasts third-party apps can't spoof, zero network calls anywhere in the dependency tree, release build is non-debuggable by default, signing is now a real (non-debug) key. The one real gap found (`allowBackup` defaulting to `true`) is tracked in §2.

## 6. Repository layout / key files

- `lib/main.dart` — Flutter entry point and app UI (capture screen, bubble, overlay state machine).
- `android/app/src/main/kotlin/.../` — native Android (unlock/lock detection receiver, overlay service, platform channels).
- `android/app/src/main/AndroidManifest.xml` — permissions + service/receiver declarations.
- `android/app/keystore/upload-keystore.jks`, `android/key.properties` — release signing (gitignored, see §5).
- `assets/icon/icon.png` — placeholder app icon source (purple lock, matches in-app bubble color; not final branding).
- `pubspec.yaml` — Dart/Flutter dependencies.
- `README.md` — repo front door: what the app is, current status, and the map to every other doc. Start here on a fresh clone.
- `docs/ARCHITECTURE.md` — system design: the three-Flutter-engine topology, native components, event flows, and the "why" behind them. **Read before touching the native layer or overlay flow.**
- `docs/PRD.md` — the current, Flutter-accurate PRD (see §2). `docs/archive/IntentLock_PRD_v1_original.md` is the original, stale v1.0 (RN/Expo/Replit), kept only for history.
- `docs/BACKLOG.md` — tactical deferred work (features/fixes/ideas + priorities). Strategic decisions stay in §11/§12 here, not there.
- `docs/SETUP.md` — Windows dev-environment bring-up (Git → Flutter SDK → Android Studio SDK-only → Claude Code → physical device).
- `CLAUDE.md` — this file (repo root; Claude Code reads it from here).

(Confirm the exact Kotlin package path after cloning and correct this section if it differs.)

## 7. Working rules (how to collaborate on this project)

- **Do NOT modify Kotlin / native Android files unless explicitly asked.** The native layer is delicate; changing it silently risks breaking things that currently work. If a task seems to require touching Kotlin, STOP and ask first, explaining why. (This has happened once already, explicitly approved — the v0.3.0 screen-lock detection change — following exactly this process: explained why Dart-only wasn't possible, named the three files, asked, then proceeded.)
- **Explain the "why," not just the "what."** I want the reasoning behind decisions, tradeoffs, and setup steps — not bare instructions.
- **Work in small, sprint-sized increments.** Plan explicitly before building. Confirm scope before creating or editing files.
- **Ask clarifying questions when scope is ambiguous** rather than guessing.
- Prefer editing existing files over adding new ones; keep the dependency count low.
- Run `flutter analyze` and test on a real device before declaring anything done.
- **Keep `docs/ARCHITECTURE.md` current.** Whenever the engine topology, native components (services/receivers), event flows, or their rationale change, update that doc in the same change — it's the durable, cross-machine record of how the system actually fits together.
- **Claude Code's local auto-memory does not sync across machines** — treat it as a same-machine convenience only. Anything that needs to survive a laptop switch or be picked up fresh belongs in this file (or elsewhere in the repo), not solely in memory.

## 8. Engineering principles — must run well on low-end AND high-end devices

This is a hard requirement, not a nice-to-have. The app runs a persistent overlay + foreground service, which is exactly where cheap devices struggle. Every change is judged against this.

- **Overlay engine cost:** `flutter_overlay_window` spins up a *second* Flutter engine for the bubble. Keep the overlay UI minimal — no heavy widgets, images, or continuous animations in the bubble. Every MB of overlay RAM matters on a 2–3 GB device.
- **Battery / foreground-service discipline:** the bubble runs via a foreground service. Do the minimum work; avoid polling/timers that wake the CPU; coalesce UI updates. Target <2% battery/day.
- **Responsive layout:** never hardcode pixel sizes. Use logical density, `MediaQuery`, and flexible layouts so it works from small budget screens to large phones and foldables.
- **Fast unlock path:** keep the unlock → prompt path lightweight so the prompt appears within ~500ms even on slow storage. Defer non-critical init off the critical path. (Known current gap: the capture screen's cold-start of the overlay's second Flutter engine, plus the close+reopen round-trip needed when collapsing to the bubble, add real latency — pre-warming the overlay engine is a parked follow-up, not yet done.)
- **Graceful degradation:** if overlay permission is denied, or an aggressive OEM (Xiaomi/Oppo/Vivo — highly relevant for the India market) kills the service, fall back to a notification-based reminder instead of failing silently. **Not built yet** — confirmed current behavior is a silent no-op if permission is missing (see `_showCaptureScreen()` in `lib/main.dart`).
- **Test matrix:** validate on at least one low-end device (≤3 GB RAM, older Android) and one modern device. Emulators do NOT reproduce unlock events or overlay behavior — physical devices only. Always test `--release`, not just debug, when judging performance. **Still outstanding as of v0.3.0:** low-end device pass (testing so far has been on a modern device only), landscape/rotation, battery soak test vs. the <2%/day target.
- **minSdk / targetSdk:** baseline is API 29 (Android 10). Going lower widens reach (meaningful for budget Android in India) but complicates the overlay stack; treat any change as a deliberate decision, not a default. Keep targetSdk current for Play compliance.

## 9. Platform & policy constraints (the fragile surface)

- The **SYSTEM_ALERT_WINDOW + AccessibilityService** permission stack is the most policy-pressured area on Android 12–16 and the single biggest existential risk to the app. Android 13+'s "Restricted Settings" gate (§5) is a concrete instance of this pressure already being felt during informal sharing, not just a theoretical Play-review risk.
- **Prefer `UsageStatsManager` over `AccessibilityService`** wherever the same signal can be obtained. Accessibility use is heavily scrutinized in Play review and can get the app pulled.
- **Onboarding is a permission cliff.** Do NOT demand overlay + accessibility on day one — that's a top drop-off risk regardless of pricing. **Whether the bubble itself is free or Pro-gated is now an open question (see §11/§12) — don't assume Pro.** The "ease into it, don't demand upfront" onboarding principle still holds either way; it's separate from the monetization decision. No onboarding flow exists yet at all — first launch just requests overlay permission with zero explanation.
- **Smart unlock triage:** don't prompt on every unlock. Skip very short/quick unlocks to avoid friction fatigue; make cooldown and triage configurable — see §3 for the concrete Sprint 3 design.

## 10. Product strategy (keep decisions anchored here)

- **Primary competitor: Intenty** — ~2-year head start, strong press coverage, 4.8★. The unlock-prompt mechanic alone is NOT a differentiator. Our wedge is bubble + timer + session framing.
- **Behavioral caveat:** the PNAS *one sec* RCT found the deliberation prompt is the *weakest* active ingredient among friction-based interventions. Do NOT rest the product thesis on the prompt. Concentrate product energy on the bubble + timer accountability loop.
- **Repositioning:** frame as a "phone session manager," which broadens the market and reduces head-to-head overlap with Intenty.
- **Kill criteria exist** (tripwires on D1 retention, permission-grant rate, Play policy actions, Intenty shipping its own bubble, conversion, NPS). Revisit these before over-investing in any direction.

## 11. Monetization — UNDECIDED (open question, see §12)

- **No model is committed.** Freemium (monthly/annual/lifetime) is the leading candidate but NOT settled. Donation-based / pay-what-you-want is also under active consideration — viability untested. Do not build code that hard-assumes a specific monetization structure (e.g., don't wire up a paywall gate around the bubble — see §9).
- The earlier "$79.99 lifetime" figure was a candidate number under a freemium assumption, not a decision — treat all specific pricing as provisional until the model itself is chosen.
- Freemium feature-gating (which features are Pro) is also open, since the bubble itself may end up free — don't hardcode a specific gating list.
- **Local-first by default stays a principle regardless of monetization model:** no analytics or network calls in the free/base experience — privacy is a selling point independent of how the app makes money. (Confirmed true as of v0.3.0: zero network calls anywhere in the dependency tree.)

## 12. Open decisions (flag these, don't assume)

- **Naming / branding (UNRESOLVED):** Started as "IntentLock" (PRD), then shifted to the working name "Why Did I Unlock." Neither is settled as the store brand. The May 2026 stress-test recommended dropping BOTH: "IntentLock" reads like a security/MDM product; "Why Did I Unlock" is a strong tagline but long, hard to search, and semantically owned by the competitor Intenty. Alternatives floated (not chosen): Sesh, Throughline, Onpurpose, Phonepoint. Decide the *store brand* before the listing. Separately, keep the *code package name* (in `pubspec.yaml` / Android `applicationId`) as whatever Sprint 1 scaffolded it to — renaming a Flutter package post-scaffold is disruptive, and the internal identifier need not match the marketed brand. Confirmed: the code package is already `why_did_i_unlock`, so only the *store brand* is still open. **The on-device app label was set to "Why Did I Unlock" for v0.3.0's informal sharing** — this is a low-risk interim choice for friend-testing, not a resolution of the store-brand question; the app icon shipped alongside it is explicitly a placeholder for the same reason.
- **iOS strategy:** the floating bubble cannot be replicated on iOS as it is on Android. iOS would be a *separate product* built on Shortcuts + Focus Filters. Decision pending: deprioritize / rebuild separately / drop.
- **PRD rewrite:** done — see `docs/PRD.md`. Re-verify it against actual code if meaningful time has passed since 2026-07-17.
- **Monetization model (UNRESOLVED):** freemium vs. donation-based vs. hybrid — not decided. See §11. To be worked through together; don't let any single sprint's code assume an answer.
- **Bubble: free vs. Pro (UNRESOLVED):** previously assumed Pro-gated; now open — may ship free. See §9/§11.
- **Delay-before-unlock / scheduling / bypass list — early-stage idea, NOT scoped, NOT committed.** Concept: add a deliberate delay when unlocking (possibly on a schedule, e.g., certain hours/contexts), with a bypass list for time-sensitive or essential actions (e.g., payments) so the friction doesn't block things that shouldn't be blocked. This is a distinct mechanic from "smart unlock triage" (§9, which *skips* prompting on short unlocks) — triage reduces friction, this idea *adds* friction deliberately, so don't conflate the two when either comes up. Needs real scoping (what triggers it, how the bypass list is defined/maintained, does it interact with the existing prompt+bubble flow or replace it for certain unlocks) before it enters any sprint.

## 13. Common commands

```
flutter doctor                 # validate environment
flutter doctor --android-licenses   # accept SDK licenses
flutter pub get                # install dependencies
flutter devices                # confirm the phone is connected
flutter run                    # run on connected device (debug)
flutter run --release          # test real-world performance (do this on the low-end device)
flutter analyze                # static analysis
flutter build apk --release    # release build (universal, larger)
flutter build apk --release --split-per-abi   # release build, one smaller APK per CPU architecture — use this for sharing
flutter clean                  # when builds get weird
```

## 14. Do NOT

- Touch Kotlin / native Android files unless explicitly asked.
- Add analytics or network calls to the free/base experience.
- Reintroduce React Native / Expo / Replit anything.
- Demand all permissions upfront in onboarding.
- Trust the PRD over this file on stack, pricing, or platform decisions.
- Assume the bubble is Pro-gated, or assume freemium is the final monetization model — both are open (§11/§12).
- Commit `android/key.properties` or the release keystore (`android/app/keystore/upload-keystore.jks`) — both are gitignored by design (§5).
- Call `sqflite` (or any other plugin) directly from overlay-isolate code (`OverlayRoot`/`overlayMain()` in `lib/main.dart`) — it will throw `MissingPluginException` (§3).
- Assume Claude Code's local memory carries over to a new machine — it doesn't (see header, §7).
