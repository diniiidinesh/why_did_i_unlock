# CLAUDE.md — Why Did I Unlock

> Operational context for Claude Code. Read this fully at the start of every session.
> Last updated: 2026-07-17. Owner: Dinesh.
> Working name: **Why Did I Unlock** (originally "IntentLock" in the PRD). The public/store brand is NOT finalized — see §9.

## 1. What this app is

Why Did I Unlock (working name) is an Android-first digital-wellbeing app. Core loop:

1. **Intent capture** — on phone unlock, a prompt asks "What are you unlocking for?" (presets / voice / custom text).
2. **Floating bubble** — the declared intent persists as a draggable overlay bubble across all apps until the user completes it.
3. **Optional timer** — a countdown can be attached; the bubble changes color / pulses as time runs out.

The defensible combination is **bubble + timer**, NOT the unlock prompt on its own (see §7). Positioning is deliberately drifting from "unlock interceptor" toward "phone session manager."

## 2. Current state — ground truth (the PRD is partly stale)

- **Stack is Flutter.** The PRD (in the repo / Drive) still describes React Native + Expo + Replit. That is obsolete. Trust THIS file over the PRD on anything stack-, pricing-, or platform-related. Flutter was chosen over RN/Expo after a feature-by-feature comparison, mainly because `flutter_overlay_window` handles the overlay + permission complexity cleanly.
- **Sprint 1 is complete but narrower than it sounds — verified against actual code on 2026-07-17.** What's built: unlock detection (`UnlockReceiver` → `UnlockListenerService` foreground service → `MainActivity` → Flutter `MethodChannel`) triggers a floating bubble via `flutter_overlay_window`. **The bubble is currently static and decorative** — a purple circle with a 🔒 emoji, no text, no intent behind it. There is NO intent-capture screen, no presets, no text/voice input, no timer, no completion flow, no local storage, no dashboard. The core product loop (declare intent → see it on the bubble → complete it) does not exist yet — Sprint 1 delivered the plumbing (unlock detection + overlay trigger), not the product on top of it. **Treat intent capture as unbuilt, not "remaining polish," when scoping Sprint 2.**
- Overlay is handled by the **`flutter_overlay_window`** package (currently `^0.5.0`).
- Target: **Q3 2026 MVP**, built incrementally, sprint by sprint.
- The PRD still needs a full rewrite for Flutter (open task, §9).
- **Code package name (confirmed from `pubspec.yaml`): `why_did_i_unlock`.** Matches the working name; no code rename needed.
- **Current dependencies are minimal** (Sprint 1 only): `flutter_overlay_window`, `cupertino_icons`. No state management, local storage, or permission-handler package added yet — those arrive in later sprints. `description` in pubspec is still the default "A new Flutter project." — update before any release build.
- **Toolchain floor:** pubspec requires Dart SDK `^3.11.5`, so install a **current stable Flutter** on the new machine. If `flutter pub get` fails with an SDK-constraint error, the Flutter version is too old — run `flutter upgrade`.
- **Manifest reality check:** `RECORD_AUDIO` / `POST_NOTIFICATIONS` are NOT yet in `AndroidManifest.xml` (voice/timer not built). The manifest DOES include `FOREGROUND_SERVICE_SPECIAL_USE` (Android 14+ requirement) — the PRD never mentions this permission; it's a real addition, not a gap.

## 3. Repository layout / key files

- `lib/main.dart` — Flutter entry point and app UI.
- `android/app/src/main/kotlin/.../` — native Android (unlock detection receiver, overlay service, platform channels).
- `android/app/src/main/AndroidManifest.xml` — permissions + service/receiver declarations.
- `pubspec.yaml` — Dart/Flutter dependencies.
- `CLAUDE.md` — this file.

(Confirm the exact Kotlin package path after cloning and correct this section if it differs.)

## 4. Working rules (how to collaborate on this project)

- **Do NOT modify Kotlin / native Android files unless explicitly asked.** The native layer (unlock receiver, overlay service) is delicate and currently working; changing it silently risks breaking Sprint 1. If a task seems to require touching Kotlin, STOP and ask first, explaining why.
- **Explain the "why," not just the "what."** I want the reasoning behind decisions, tradeoffs, and setup steps — not bare instructions.
- **Work in small, sprint-sized increments.** Plan explicitly before building. Confirm scope before creating or editing files.
- **Ask clarifying questions when scope is ambiguous** rather than guessing.
- Prefer editing existing files over adding new ones; keep the dependency count low.
- Run `flutter analyze` and test on a real device before declaring anything done.

## 5. Engineering principles — must run well on low-end AND high-end devices

This is a hard requirement, not a nice-to-have. The app runs a persistent overlay + foreground service, which is exactly where cheap devices struggle. Every change is judged against this.

- **Overlay engine cost:** `flutter_overlay_window` spins up a *second* Flutter engine for the bubble. Keep the overlay UI minimal — no heavy widgets, images, or continuous animations in the bubble. Every MB of overlay RAM matters on a 2–3 GB device.
- **Battery / foreground-service discipline:** the bubble runs via a foreground service. Do the minimum work; avoid polling/timers that wake the CPU; coalesce UI updates. Target <2% battery/day.
- **Responsive layout:** never hardcode pixel sizes. Use logical density, `MediaQuery`, and flexible layouts so it works from small budget screens to large phones and foldables.
- **Fast unlock path:** keep the unlock → prompt path lightweight so the prompt appears within ~500ms even on slow storage. Defer non-critical init off the critical path.
- **Graceful degradation:** if overlay permission is denied, or an aggressive OEM (Xiaomi/Oppo/Vivo — highly relevant for the India market) kills the service, fall back to a notification-based reminder instead of failing silently.
- **Test matrix:** validate on at least one low-end device (≤3 GB RAM, older Android) and one modern device. Emulators do NOT reproduce unlock events or overlay behavior — physical devices only. Always test `--release`, not just debug, when judging performance.
- **minSdk / targetSdk:** baseline is API 29 (Android 10). Going lower widens reach (meaningful for budget Android in India) but complicates the overlay stack; treat any change as a deliberate decision, not a default. Keep targetSdk current for Play compliance.

## 6. Platform & policy constraints (the fragile surface)

- The **SYSTEM_ALERT_WINDOW + AccessibilityService** permission stack is the most policy-pressured area on Android 12–16 and the single biggest existential risk to the app.
- **Prefer `UsageStatsManager` over `AccessibilityService`** wherever the same signal can be obtained. Accessibility use is heavily scrutinized in Play review and can get the app pulled.
- **Onboarding is a permission cliff.** Do NOT demand overlay + accessibility on day one — that's a top drop-off risk. Make the **bubble an opt-in Pro feature**, earned after the user has seen value, rather than a required upfront grant.
- **Smart unlock triage:** don't prompt on every unlock. Skip very short/quick unlocks to avoid friction fatigue; make cooldown and triage configurable.

## 7. Product strategy (keep decisions anchored here)

- **Primary competitor: Intenty** — ~2-year head start, strong press coverage, 4.8★. The unlock-prompt mechanic alone is NOT a differentiator. Our wedge is bubble + timer + session framing.
- **Behavioral caveat:** the PNAS *one sec* RCT found the deliberation prompt is the *weakest* active ingredient among friction-based interventions. Do NOT rest the product thesis on the prompt. Concentrate product energy on the bubble + timer accountability loop.
- **Repositioning:** frame as a "phone session manager," which broadens the market and reduces head-to-head overlap with Intenty.
- **Kill criteria exist** (tripwires on D1 retention, permission-grant rate, Play policy actions, Intenty shipping its own bubble, conversion, NPS). Revisit these before over-investing in any direction.

## 8. Monetization

- Freemium: monthly, annual, and lifetime tiers.
- **Lifetime priced ≥ $79.99.** The PRD's $59.99 is outdated and underpriced.
- Free tier must still deliver the core value; gate power features (bubble customization, voice-to-text, analytics, advanced timer) behind Pro.
- Local-first by default: no analytics or network calls in the free tier — privacy is a selling point.

## 9. Open decisions (flag these, don't assume)

- **Naming / branding (UNRESOLVED):** Started as "IntentLock" (PRD), then shifted to the working name "Why Did I Unlock." Neither is settled as the store brand. The May 2026 stress-test recommended dropping BOTH: "IntentLock" reads like a security/MDM product; "Why Did I Unlock" is a strong tagline but long, hard to search, and semantically owned by the competitor Intenty. Alternatives floated (not chosen): Sesh, Throughline, Onpurpose, Phonepoint. Decide the *store brand* before the listing. Separately, keep the *code package name* (in `pubspec.yaml` / Android `applicationId`) as whatever Sprint 1 scaffolded it to — renaming a Flutter package post-scaffold is disruptive, and the internal identifier need not match the marketed brand. Confirmed: the code package is already `why_did_i_unlock`, so only the *store brand* is still open — the code needs no rename regardless of what brand is chosen.
- **iOS strategy:** the floating bubble cannot be replicated on iOS as it is on Android. iOS would be a *separate product* built on Shortcuts + Focus Filters. Decision pending: deprioritize / rebuild separately / drop.
- **PRD rewrite:** verified stale against actual code (2026-07-17) — confirm every point still holds before drafting `PRD_flutter.md`: header tech stack + all of Appendix 6.1 "Replit Development Notes" (no `BubbleService.kt`, overlay is a plugin not hand-rolled); state-mgmt/storage rows (Zustand/Riverpod, sqflite/expo-sqlite) are aspirational, nothing installed; RN/Expo appendix packages have no Flutter equivalents in `pubspec.yaml`; Bubble API is framed as primary in the PRD's risk mitigation but the real implementation only uses `SYSTEM_ALERT_WINDOW`; $59.99 lifetime pricing is superseded (see §8). What still holds from the original PRD: the unlock-detection approach (`BroadcastReceiver` + `ACTION_USER_PRESENT`), the three baseline Android permissions, and essentially all of §1–§3.3 (persona/market/competitive content). **Critically: the new PRD's Sprint 2 scope must treat intent capture as net-new, not "add polish to existing capture" — see §2.**

## 10. Common commands

```
flutter doctor                 # validate environment
flutter doctor --android-licenses   # accept SDK licenses
flutter pub get                # install dependencies
flutter devices                # confirm the phone is connected
flutter run                    # run on connected device (debug)
flutter run --release          # test real-world performance (do this on the low-end device)
flutter analyze                # static analysis
flutter build apk --release    # release build
flutter clean                  # when builds get weird
```

## 11. Do NOT

- Touch Kotlin / native Android files unless explicitly asked.
- Add analytics or network calls to the free tier.
- Reintroduce React Native / Expo / Replit anything.
- Demand all permissions upfront in onboarding.
- Trust the PRD over this file on stack, pricing, or platform decisions.
