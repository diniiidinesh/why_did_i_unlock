**PRODUCT REQUIREMENTS DOCUMENT**

**Why Did I Unlock** *(working name — store brand not finalized, see §9)*

*Know Why You Picked Up Your Phone*

| Field | Details |
|---|---|
| Version | 2.0 (Flutter rewrite) |
| Supersedes | v1.0, Feb 27 2026 (`IntentLock_PRD.md`, written for React Native/Expo/Replit) |
| Date | July 17, 2026 |
| Status | Living document — sections marked **OPEN** are genuinely undecided, not placeholders |
| Platform | Android (Phase 1, active). iOS — undecided, see §9 |
| Tech Stack | **Flutter** (`why_did_i_unlock` package) |
| Target Launch | Q3 2026 (MVP) |

> **How to read this document:** unlike v1.0, this PRD distinguishes between three states throughout: **Built** (verified against actual code), **Planned** (scoped, not yet built), and **OPEN** (a real decision that hasn't been made — don't treat as settled). This distinction matters more than usual here because v1.0 asserted several things as decided that turned out not to be true against the actual codebase. See `CLAUDE.md` for the fuller working context this PRD summarizes product-side.

---

## 1. Idea Evaluation

### 1.1 Concept Summary

Why Did I Unlock is a digital wellbeing app built around three mechanics:

1. **Intent capture at unlock** — on phone unlock, a prompt asks "What are you unlocking for?" The user states intent via preset, custom text, or voice. *(Planned — not yet built; see §2.)*
2. **Persistent floating bubble** — the declared intent stays visible as a draggable overlay across all apps until completed. *(Partially built — the overlay mechanism itself works; it does not yet display intent text. See §2.)*
3. **Optional timer accountability** — an optional countdown attached to the declared intent, with visual urgency cues as it runs out. *(Planned.)*

The defensible combination is the **bubble + timer working together** — not the unlock prompt in isolation. This distinction matters because of a specific finding from behavioral research (§1.6) and because the closest competitor already owns the "prompt on unlock" mechanic.

### 1.2 Problem Statement

The average person unlocks their phone 80–150 times per day, and a large share of these unlocks are habitual rather than purposeful — people pick up their phone for one reason and drift into something else, losing time they didn't intend to spend. Existing solutions (app blockers, screen-time limits, grayscale modes) are largely punitive: they restrict behavior after the fact rather than building awareness at the moment of the unlock itself. There isn't a mainstream app that combines intent declaration *at the moment of unlock* with persistent visual accountability (the bubble) and optional time-bound commitment (the timer) in one flow.

### 1.3 Competitive Landscape

| App | What It Does | Key Gap This App Fills |
|---|---|---|
| **Intenty** (primary competitor) | Full-screen nudge on unlock asking "why?"; logs answers; breathing exercises | No persistent bubble reminder — intent disappears once dismissed; no timer accountability |
| One Sec | Forces a pause/breathing exercise before opening specific apps | Only triggers on specific apps, not all unlocks; no intent logging or bubble |
| Forest | Gamified focus timer; penalizes phone use during a session | Opt-in sessions only; doesn't intercept unlocks; no intent tracking |
| ScreenZen | Adds friction/delay before opening distracting apps | App-specific, not unlock-level; no persistent overlay |
| Minimalist Phone | Replaces launcher with a minimal UI | Full phone replacement — too extreme for most users; no intent tracking |
| Google Digital Wellbeing | Built-in screen-time dashboard, app timers, focus mode | Passive reporting; no active intent capture; no bubble |

**Primary competitor risk:** Intenty has roughly a 2-year head start, strong press coverage, and a 4.8★ rating. The unlock-prompt mechanic alone is not a defensible differentiator — Intenty already does it, and does it well. The wedge here is the bubble + timer combination, which Intenty doesn't have, reportedly among the most-requested features in Intenty's own user feedback.

### 1.4 Unique Value Proposition

The intended UVP is combining three mechanics that no direct competitor currently combines:

1. **Intent capture at unlock** — a prompt that captures *why* the phone is being used, via tap or voice.
2. **Persistent floating bubble** — the declared intent stays visible as an overlay across all apps until manually completed.
3. **Optional timer accountability** — a deadline attached to the task, with the bubble changing visual state as time runs low.

### 1.5 Repositioning

Framing this as a **"phone session manager"** rather than an "unlock interceptor" broadens the addressable positioning and reduces direct head-to-head framing against Intenty, which owns the "unlock nudge" category association.

### 1.6 Behavioral Research Caveat — important, keep this anchored

The PNAS *one sec* randomized controlled trial found that the deliberation prompt is the **weakest** active ingredient among friction-based interventions tested. This directly informs product strategy: **the product thesis should not rest on the prompt alone.** Product energy should concentrate on the bubble + timer accountability loop, since that's both the more defensible mechanic competitively and the one with a better behavioral case.

### 1.7 SWOT Snapshot

| | |
|---|---|
| **Strengths** | Novel mechanic combining intent + bubble + timer; privacy-first (local data by default); low-friction input options |
| **Weaknesses** | Relies on Android overlay permissions (SYSTEM_ALERT_WINDOW), which is a policy-fragile surface (§6); friction-fatigue risk if unlock prompting isn't tuned; no true iOS bubble equivalent |
| **Opportunities** | Digital-detox and screen-time-monitoring markets are both growing; potential future B2B angle (corporate wellness) — not scoped |
| **Threats** | Intenty shipping its own bubble feature would erode the core differentiator (this is one of the defined kill-criteria triggers — see §7); platform owners (Google/Apple) could build native equivalents |

---

## 2. Current Implementation State (ground truth — verified on real device, 2026-07-17)

v1.0 of this PRD asserted things about "Sprint 1" that weren't accurate against the actual codebase. This section has since been verified end-to-end on a physical device in `--release` mode — treat it as trustworthy, but re-verify against code if meaningful time has passed since the date above.

**Built and confirmed working (Sprint 1 + Sprint 2, real-device `--release` test):**
- Unlock detection: `UnlockReceiver` → `UnlockListenerService` (foreground service) → `MainActivity` → Flutter `MethodChannel`.
- Intent-capture screen appears on unlock (presets / custom text).
- **The floating bubble displays the actual declared intent text** — the earlier decorative purple-circle placeholder has been superseded.
- Bubble persists across app switches, with one confirmed OS-level exception: it does not render over the Settings app, which is expected Android anti-"tapjacking" behavior (suppressing overlays on sensitive system screens since Android 12) — not a defect.
- Manual completion works: tapping the bubble and marking an intent done clears it.
- **Single-active-intent behavior is confirmed and intentional:** unlocking again while an intent is still incomplete does not re-trigger a fresh capture screen — the existing bubble simply persists. A new capture screen only appears once the current intent is completed. This is a real product/behavioral constraint to design around in Sprint 3+ (e.g. smart triage and cooldown logic should compose with this, not assume every unlock gets a fresh prompt).
- Foreground service survived a background-kill test on a Realme/ColorOS device after a manual app reopen. **OEM battery-optimization exemption and autostart are not yet configured/tested for long-running reliability** — treat background survival as demonstrated short-term, not yet production-hardened.

**Not yet built:**
- Voice input.
- Timer / countdown.
- Local storage / intent history (so completed intents aren't persisted yet — they clear but aren't logged anywhere).
- Dashboard / analytics.

**Current dependencies:** `flutter_overlay_window`, `cupertino_icons`. No state-management, local-storage, or permission-handler package installed yet — anything beyond this should be checked against the current `pubspec.yaml` rather than assumed from this document.

---

## 3. Target Audience

| Persona | Description | Pain Point | Key Need |
|---|---|---|---|
| The Doomscroller | 18–34, heavy social media user | Picks up phone for one thing, loses significant time to social apps | A visible reminder of original intent |
| The Productivity Seeker | 25–45, knowledge worker | Blurred work/personal boundary; unlocks derail focus | Time-boxed phone sessions with accountability |
| The Digital Wellness Parent | 30–50, modeling habits for kids | Wants to demonstrate intentional tech use | Simple, non-punitive awareness tool |
| The Student | 16–24, studying with phone as a constant distraction | Unlocks to check one notification, ends up elsewhere | Quick intent capture + persistent nudge |

*(Retained from v1.0 — this content was confirmed as not stack-dependent and still holds.)*

---

## 4. Technical Architecture

### 4.1 Stack (Built / Confirmed)

| Layer | Technology | Status |
|---|---|---|
| Framework | Flutter | Built. Chosen over React Native/Expo after a feature-by-feature comparison — `flutter_overlay_window` handles overlay + permission complexity more cleanly than the RN/Expo equivalent path. |
| Overlay/Bubble | `flutter_overlay_window` package, backed by Android `SYSTEM_ALERT_WINDOW` | Built (decorative bubble only — see §2). |
| Unlock Detection | Native Kotlin: `BroadcastReceiver` for `ACTION_USER_PRESENT` → foreground service → Flutter via `MethodChannel` | Built. |
| State Management | **OPEN — not yet chosen.** v1.0 named Riverpod as a candidate; that was aspirational, not a decision. Choose when the app's state needs actually require it, not preemptively. | Not built |
| Local Storage | **OPEN — not yet chosen.** `sqflite` is a plausible Flutter-native candidate for local intent history; not installed or decided. | Not built |
| Voice Input | Android `SpeechRecognizer` API (on-device, no network) — plausible approach, not yet implemented | Not built |
| Analytics | None. Per product principle (§8), no analytics or network calls in the base/free experience regardless of monetization outcome. | N/A by design |

### 4.2 Key Android Permissions

**Confirmed present in `AndroidManifest.xml`:**
- `SYSTEM_ALERT_WINDOW` — draw the overlay bubble on top of other apps.
- `FOREGROUND_SERVICE` — keep the bubble/unlock-listener alive when backgrounded.
- `FOREGROUND_SERVICE_SPECIAL_USE` — Android 14+ requirement for this foreground-service use case. **Not mentioned in v1.0** — a real addition the original PRD didn't anticipate, not a gap in implementation.

**Not yet present (needed only once the corresponding feature is built):**
- `RECORD_AUDIO` — for voice input (not yet built).
- `POST_NOTIFICATIONS` — for timer alerts (not yet built).

**To confirm directly against the manifest rather than assume:** `RECEIVE_BOOT_COMPLETED` (auto-start after reboot) — listed as a requirement in v1.0 but not independently reverified for this rewrite.

### 4.3 Platform & Policy Constraints — the most fragile part of the technical picture

- The **SYSTEM_ALERT_WINDOW + AccessibilityService** permission stack is the single most policy-pressured surface on Android 12–16, and represents the biggest existential platform risk to this app.
- **Prefer `UsageStatsManager` over `AccessibilityService`** wherever the same signal can be obtained — Accessibility usage draws heavy Play Store review scrutiny and carries real risk of app removal.
- **Onboarding must not front-load a permission cliff.** Demanding overlay (and potentially accessibility) permissions on day one is a known high-drop-off pattern. Whether the bubble itself ends up free or paywalled is a separate, currently open question (§8) — either way, the onboarding sequencing principle holds: earn the permission ask, don't front-load it.
- **Smart unlock triage:** prompting on every single unlock risks friction fatigue. Very short/quick unlocks should likely be skippable, with cooldown/triage configurable. *(Distinct from the delay-before-unlock idea in §9 — triage reduces friction, that idea deliberately adds it; don't conflate the two.)*

### 4.4 Non-Functional Requirements — device-performance floor

This app runs a persistent overlay and a foreground service, which is exactly where low-end devices struggle, so these aren't aspirational — they're a hard bar:

| Requirement | Target |
|---|---|
| Unlock-to-prompt latency | Prompt/overlay renders within ~500ms of unlock, even on slower storage |
| Overlay memory footprint | `flutter_overlay_window` spins up a second Flutter engine for the bubble — keep its UI minimal (no heavy widgets/animations); every MB matters on a 2–3GB device |
| Battery | Foreground service should do minimum necessary work; avoid polling/wake timers; target <2% battery/day |
| Responsiveness | No hardcoded pixel sizing; use logical density / `MediaQuery` so layout holds from budget screens to foldables |
| Device coverage | Test on at least one low-end device (≤3GB RAM, older Android) and one modern device — **never rely on emulators** for unlock or overlay behavior, they don't reproduce it. Always verify `--release` build performance, not just debug. |
| minSdk / targetSdk | Baseline API 29 (Android 10). Lowering further widens reach (relevant for budget Android, especially in the India market) but complicates the overlay stack — treat as a deliberate call, not a default. |
| OEM resilience | Aggressive OEMs (Xiaomi/Oppo/Vivo) are known to kill background services. If overlay permission is denied or the service is killed, degrade gracefully to a notification-based reminder rather than failing silently. |

---

## 5. User Flows

### Flow 1: First-Time Setup *(Planned)*

1. User installs the app.
2. Onboarding explains the concept without front-loading every permission request at once (§4.3).
3. Guided, staged permission setup: overlay → notifications → (optional) microphone, requested as needed rather than all at once.
4. User configures a small set of default intent presets.
5. Setup complete; user locks the phone to test the flow.

### Flow 2: Standard Unlock — Core Loop *(Confirmed working on real device, 2026-07-17 — see §2)*

1. User unlocks phone.
2. Intent-capture prompt appears: preset buttons + custom text field (+ voice, if/when built).
3. User declares intent via tap, custom text, or voice.
4. (Optional, future) User attaches a timer.
5. Prompt dismisses; the floating bubble now displays the declared intent (this is the piece that closes the gap identified in §2 — a bubble with actual content, not the decorative placeholder).
6. User proceeds; bubble persists across all apps.
7. User taps the bubble, marks it done; intent is logged (once storage exists).

### Flow 3: Timer Expiry *(Planned, P1 — not scoped for the current sprint)*

Countdown reaches visual thresholds (e.g., approaching expiry → expired), bubble changes state accordingly, and a notification prompts the user to confirm completion or extend.

---

## 6. Feature Specification

### P0 — Core loop (MVP-critical)

| Feature | Status | Notes |
|---|---|---|
| Unlock Detection | **Built & confirmed** | Sprint 1. Verified reliable across repeated unlock cycles on real device. |
| Floating Bubble (mechanism) | **Built & confirmed** | Sprint 1. |
| Intent Capture Screen (presets + custom text) | **Built & confirmed** | Sprint 2. Verified on real device, `--release` build. |
| Bubble displaying declared intent | **Built & confirmed** | Sprint 2. Bubble now shows actual intent text; decorative placeholder is superseded. |
| Manual Completion (mark intent done) | **Built & confirmed** | Sprint 2. Tapping bubble → mark done → bubble clears, verified working. |
| Single-active-intent behavior | **Built & confirmed (by design)** | A fresh unlock while an intent is incomplete does not re-trigger capture — existing bubble persists until completed. Design a decision for Sprint 3+ features to respect, not a bug. |
| Intent History (local log) | **Planned** | Needs a storage decision first (§4.1) — intents currently clear on completion without being logged anywhere. |
| Cooldown / smart triage | **Planned** | See §4.3. |

### P1 — Should have (post-MVP core loop)

| Feature | Description |
|---|---|
| Timer | Optional countdown with visual urgency states and expiry notification. |
| Voice-to-Text Input | On-device speech recognition for intent entry. |
| Bubble Customization | Color/size/opacity — **only relevant once the free-vs-Pro question (§8) is resolved**, since this was previously assumed to be a Pro-gated feature and that's no longer settled. |
| Basic Analytics Dashboard | Local-only unlock counts, completion rate, etc. |

### P2 — Under active consideration, NOT scoped

| Idea | Status |
|---|---|
| **Delay-before-unlock, with scheduling and a bypass list** — a deliberate friction gate on unlock (potentially time-of-day/context-scheduled), with an allowlist for essential/time-sensitive actions like payments so the friction doesn't block things it shouldn't. | Early-stage idea, explicitly not committed. Needs real scoping: what triggers it, how the bypass list is defined and maintained, and how it interacts with (or replaces) the existing prompt+bubble flow for a given unlock. Distinct mechanic from smart triage (§4.3) — triage *removes* friction, this *adds* it deliberately. |
| Gamification (streaks, badges) | Not scoped. |
| Widget / home-screen summary | Not scoped. |
| iOS support | See §9 — not just unscoped but strategically undecided. |

---

## 7. Product Strategy — anchor points

- **Primary competitor:** Intenty (§1.3). The unlock-prompt mechanic alone is not defensible; the wedge is bubble + timer + session-manager framing.
- **Don't rest the thesis on the prompt** — see the PNAS *one sec* finding (§1.6).
- **Kill-criteria exist** as tripwires: D1 retention, permission-grant rate, Play Store policy actions taken against the app, Intenty shipping its own bubble feature, conversion rate (once a monetization model exists), and NPS. These should be revisited before over-investing in any single direction, and reconsidered explicitly once §8 and §9's open questions are resolved, since several tripwires (conversion rate in particular) are contingent on a monetization model existing at all.

---

## 8. Monetization — OPEN, not decided

This section is deliberately non-committal, because it isn't settled:

- **No model is committed.** Freemium (tiered, e.g. monthly/annual/lifetime) is the leading candidate but not decided. Donation-based / pay-what-you-want is also under active consideration, with viability genuinely untested.
- **The bubble's free-vs-Pro status is open** — earlier framing assumed it would be Pro-gated; that's no longer a safe assumption. Don't build a paywall around it preemptively.
- Any pricing figures that surface in planning (e.g., a lifetime-tier number) should be treated as provisional scratch numbers under a freemium *hypothesis*, not commitments, until the model itself is chosen.
- **One principle holds regardless of which model wins:** local-first by default — no analytics or network calls in the base/free experience. This is a privacy stance independent of how the app eventually makes money.

*When this is resolved, this section should be rewritten with an actual decision, a rationale, and — if freemium — a real feature-gating table. Until then, don't let any single sprint's implementation quietly assume an answer.*

---

## 9. Open Decisions — the honest list

| Decision | Status |
|---|---|
| **Store brand / naming** | Started as "IntentLock," working name shifted to "Why Did I Unlock." Neither is settled as the public store brand — both have real drawbacks (IntentLock reads as a security/MDM product; "Why Did I Unlock" is a strong tagline but long, hard to search, and semantically close to Intenty). Code package name (`why_did_i_unlock`) is unaffected either way — it doesn't need to match the eventual store brand. |
| **iOS strategy** | The floating-bubble mechanic cannot be replicated on iOS the way it works on Android — it would need to be rebuilt on Shortcuts + Focus Filters, effectively making it a separate product. Undecided whether to deprioritize, build separately, or drop. |
| **Monetization model** | Freemium vs. donation-based vs. hybrid — see §8 in full. |
| **Bubble: free or Pro** | See §8. Previously assumed Pro; now open. |
| **Delay-before-unlock / scheduling / bypass list** | Early-stage idea, not scoped — see §6, P2. |
| **State management & local storage choice** | Not yet needed until Sprint 2/3 functionality requires them; don't pre-select out of habit. |

---

## 10. Success Metrics

Retained from v1.0 as directional targets — **note that Pro Conversion Rate is contingent on a monetization model existing (§8)** and should be reconsidered once that's resolved, rather than tracked against a model that may not be the one shipped.

| Metric | Month 1 | Month 6 | Month 12 |
|---|---|---|---|
| Downloads | 5,000 | 50,000 | 200,000 |
| DAU/MAU Ratio | 30% | 35% | 40% |
| D7 Retention | 25% | 35% | 40% |
| D30 Retention | 10% | 18% | 25% |
| Pro Conversion Rate *(if applicable — see caveat above)* | 3% | 7% | 10% |
| App Store Rating | 4.0+ | 4.3+ | 4.5+ |

---

## 11. Appendix

### 11.1 Development Environment

Superseded by `SETUP.md` in the repo root, which documents the actual Windows/Flutter/Android toolchain setup in detail. This PRD no longer carries Replit-specific setup notes (v1.0's Appendix 6.1) — they don't apply to the current stack and referencing them risks someone following stale instructions.

### 11.2 Monetization Alternatives Considered

| Model | Status |
|---|---|
| Freemium (tiered) | Leading candidate — not committed. See §8. |
| Donation-based / pay-what-you-want | Under active consideration — not committed, viability untested. See §8. |
| One-time purchase only | Previously offered as a Lifetime tier *within* a freemium structure, not a standalone model; revisit once §8 is resolved. |
| Ads | Rejected — contradicts the app's digital-wellness positioning and privacy stance. |
| B2B licensing | Not scoped for MVP; a possible future direction, not a current plan. |

### 11.3 Key References

1. Intenty (Google Play) — primary competitor reference for unlock-based intent capture.
2. Android Bubble API documentation — `developer.android.com/develop/ui/views/notifications/bubbles`.
3. PNAS *one sec* RCT — behavioral efficacy research on friction-based interventions (§1.6).
4. `CLAUDE.md` (repo root) — the fuller, more frequently updated working-context document this PRD summarizes for product purposes. If the two ever disagree, treat `CLAUDE.md` as more current unless this PRD has a later revision date.

*End of Document — v2.0*
