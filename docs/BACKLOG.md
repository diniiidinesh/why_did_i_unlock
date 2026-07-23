# BACKLOG — Why Did I Unlock

> Deferred engineering/feature work and ideas not yet built. Git-tracked on purpose
> (survives machine switches).
>
> **Sprint 3 shipped (v0.5.0+7, merged to `main` 2026-07-22).** Local intent-history
> storage (`sqflite`, `intent_log`), prompt-frequency triage (1-min cooldown + 50% prob),
> and minimal read-only history view are all built, tested (27/27 pass, all manual
> on-device cases verified), and live. Four real bugs found and fixed during the build
> are now documented as gotchas in `ARCHITECTURE.md` §5 and `CLAUDE.md` §3:
> (1) `shareData()` must be fire-and-forget, never awaited, from overlay isolate.
> (2) `FlutterOverlayWindow.isActive()` native hang — replaced with self-tracked
>     `_overlayIsActive` bool + overlay-closed signal.
> (3) sqflite's `singleInstance: true` meant History screen's close closed the writer's
>     connection; fixed via `ownConnection` parameter.
> (4) Direct-boot service can start before credential-encrypted storage is unlocked
>     (`errno 126 ENOKEY`), causing permanent `_intentStore` null; fixed via idempotent
>     `_ensureIntentStore()` retry at write-time + triage-check-time.
> Full analysis: `docs/debug/sprint3-session-log-2026-07-22.txt` UPDATEs 1–4.
>
> **Scope:** this file holds *tactical* backlog — features, fixes, polish, ideas.
> For **strategic open decisions** (monetization model, store brand, iOS strategy,
> bubble free-vs-Pro, delay-before-unlock) see **`CLAUDE.md` §11/§12** — the single
> source of truth for those; not duplicated here to avoid drift. For the **next
> sprint's committed scope** (local storage + cooldown) see **`CLAUDE.md` §3**.

Priority tags: **[P1]** = do soon / alongside related work · **[P2]** = worthwhile, not urgent · **[explore]** = needs real scoping before it's buildable · **[decision]** = needs a product call before building.

---

## Reliability / correctness

- **[DONE 2026-07-23] Restart monitoring after an app update** — `UpdateReceiver` added, listening for `ACTION_MY_PACKAGE_REPLACED` and restarting `UnlockListenerService`. Found via an on-device build push during Sprint 4: `flutter run` always auto-launches after install, which masked that a real update (Play push, or a manually installed APK) left monitoring dead until the user reopened the app — distinct mechanism from the reboot gap (no "stopped state" involved). Verified on-device (`docs/TEST_PLAN.md` case 45) — **but with an unresolved caveat**: the fix worked reliably once the app had been opened at least once since boot; the very first reinstall attempt on a fully-dormant process produced no trace of the receiver firing at all, not yet explained. Not reproduced a second time, but flagged in case it recurs. See `docs/ARCHITECTURE.md` §2.

- **[DONE 2026-07-22] `android:allowBackup="false"`** — SHIPPED alongside Sprint 3 storage (was unset/defaulting to `true`). Prevents Android auto-backup from sweeping up intent history.
- **[P1] OEM autostart onboarding** — aggressive OEMs (Xiaomi/Oppo/Vivo, key India market) block boot auto-restart AND kill the foreground service during normal use unless the user manually grants "Autostart" / disables battery optimization. Not fixable in code — needs a guided in-app screen walking the user through the OEM-specific setting. Fixes both the reboot gap on those OEMs and the general process-kill reliability gap. (Was "Option C" in the reboot discussion.)
- **[DONE 2026-07-21] `LOCKED_BOOT_COMPLETED` (direct boot)** — SHIPPED. `BootReceiver` + `UnlockListenerService` are now `directBootAware` and handle `LOCKED_BOOT_COMPLETED`, so monitoring starts before the first post-reboot unlock. Verified across 2 real reboots (prompt appeared ~2s after boot, zero manual app-open). The device-encrypted-storage concern turned out moot: our logic only runs on `ACTION_USER_PRESENT`, which fires after unlock when normal storage is already available.
- **[P2] Graceful degradation when overlay permission is denied/revoked** — currently a silent no-op (confirmed). CLAUDE.md §8 calls for a notification-based fallback instead. Not built.

## Storage / history (Sprint 3 — DONE)

- **[DONE 2026-07-22] Overlay write path, IsolateNameServer relay, and concurrent-open guard** — Bugs 1–4 found and fixed (see summary above). Write path now reliably delivers every event across multiple dismiss cycles, even after swipe-away and reboot. Verified end-to-end with 27 automated tests + 24 manual on-device cases.
- **[DONE 2026-07-22] Prompt-frequency triage** — cooldown (1 min) + probability (50%) composite, both verified working correctly against real event data. Triage gate plugs into `_showCaptureScreen`, inputs validated fresh per unlock.
- **[DONE 2026-07-22] Minimal history view** — `lib/history_screen.dart` reads from the DB, renders events newest-first, styles no-intent rows distinctly. Verified against real multi-event data on-device.
- **[P2] Triage customization UI** — settings screen exposing cooldown/probability (and eventually instance-based) tuning, mirroring the intent-preset UI pattern. Architecture is ready for this (`CompositePromptPolicy` in `lib/prompt_policy.dart`) — deferred because it's competitor Intenty's turf, not this app's differentiator, and there's no usage data yet to pick better defaults than the current 1min/50%.
  - **Probability options:** Everytime (100%), 75%, 50% (current default), 25%, Never (0%) — or custom percentage input.
  - **Cooldown options:** No cooldown (0 min), 1 min (current default), 2 min, 5 min, 10 min — or custom duration input.
- **[explore] Instance-based triage strategy** (e.g. "skip every Nth unlock") — a third `PromptPolicy` implementation alongside cooldown/probability; same architecture, not yet built.
- **[P2] `status` (completed-vs-abandoned) on `intent_log`** — deferred until the UI actually supports more than one dismiss gesture (still just the × badge).

## Performance (must run on low-end devices — CLAUDE.md §8)

- **[P2] Overlay engine pre-warm** — first capture screen after unlock is slow (cold-starts the overlay's second Flutter engine); the dismiss close+reopen adds a native round-trip. Investigate pre-warming at app start. Ties to the ~500ms unlock-path target.
- **[P2] Untested surfaces** — landscape/rotation (capture screen + pill), low-end-device pass (≤3GB, older Android — only tested on a modern Nothing Phone so far), battery soak vs. the <2%/day target.
- **[P2] Overlay engine cold-start latency** — the overlay's second Flutter engine spins up on each `showOverlay()` call, adding observable (device-dependent, but ~1–2s on some runs per on-device tests 2026-07-22) latency between unlock→capture-screen-visible. Pre-warming the overlay engine at app startup (best-effort, non-blocking) could eliminate that. Known architectural limitation (CLAUDE.md §8); deferred to Sprint 4 since the core functionality works, just slowly.
- **[P2] Config-relay (T11) reply latency after a fresh process start** — observed on-device 2026-07-23: right after reopening the app post-force-stop, the capture screen showed **only** "Just Like That" with no preset pills for long enough to be noticed and interacted with, not the "sub-second, imperceptible" window `docs/DATA_MODEL.md` §4 describes. Not a bug — it's the documented, deliberately-valid zero-presets state (`docs/TEST_PLAN.md` case 54's note) — but the *duration* exceeded expectations. Likely cause: the background isolate has to cold-open the database (no warm cache yet, right after a fresh process start) before it can even fetch presets to reply with, so the request→reply round trip is slower immediately post-restart than during a long-running warm process. Not root-caused with logs yet (would need a `flutter run` session with logcat watching the exact reopen-then-unlock moment). Worth checking whether this is consistently reproducible, and if so, whether it's worth special-casing (e.g. render nothing extra, just confirm the delay is bounded) or folding into the overlay pre-warm work above, since both share the same root cause (cold engine start after a fresh process).

## Capture-screen / bubble UX

- **[DONE 2026-07-21] "OK"/submit button** — SHIPPED next to the text field.
- **[DONE 2026-07-21] "Just Like That" option** — SHIPPED (logs a purposeless unlock, closes without a bubble). Styling follow-up is item #2 at top of file.
- **[DONE 2026-07-21] Prompt on/off master toggle** — SHIPPED (HomeScreen switch, `shared_preferences`, `_shouldPrompt()` gate). Scheduling to plug into that same gate is a future item; see `CLAUDE.md` §3-adjacent notes.
- **[DONE 2026-07-21] Meaningful presets** — Payments/Calls/Messages/Food Order/Commute replaced the vague originals.
- **[DONE 2026-07-21] Capture-screen keyboard handling revamp** — The interim v0.4.0 fix just shifted the whole column up, pushing presets off-screen. Now uses thumb-zone layout: title/presets/"Just Like That" bottom-anchor within scrollable space (LayoutBuilder + ConstrainedBox + IntrinsicHeight + mainAxisAlignment.end), text field pinned as footer just above keyboard. In PR #6, pending merge.
- **[DONE 2026-07-21] "Just Like That" pill styling** — Was a bare italic `TextButton`; now a real outlined pill (muted relative to topic presets so it still reads as the distinct "no real reason" option). In PR #6, pending merge.
- **[explore] Randomize preset pill order** — Presets appear in fixed order every unlock; muscle-memory tapping ("I always hit the second pill because it's Calls") is low-deliberation behavior. Prompt-timing randomization (shipped via probability gate) fights habituation by making timing unpredictable, which the research shows is neurologically effective and harmless. Position-randomization fights muscle memory but risks backfire: if pills are hard to locate, users might skip thinking and just hit "Just Like That" from friction rather than honesty — fixing one habituation by inducing another. Only builds if position-randomness is bounded (shuffle within session? vary per boot?) not truly random per-unlock. Needs UX evaluation first.
- **[P2] Drag / edge-snap behavior** — the bubble can be dragged to extreme/partly-offscreen edges. Consider Messenger-style edge-snap (`positionGravity` supports left/right/auto) and/or guaranteeing the × stays reachable.
- **[P2] Adaptive bubble sizing** — width should adapt to intent text up to a max before truncating; consider a smaller-but-legible font. Currently fixed 200×56dp, single line, 14sp, ellipsis.
- **[P2] Smaller footprint + richer actions** — shrink the bubble's on-screen footprint; consider replacing the single × with separate **Done** and **Snooze** actions.
- **[explore] Icon + tap-to-expand hybrid bubble** — each intent gets its own icon; collapsed bubble shows just the icon, tap expands to full text (Messenger chat-head style). Readable pill was chosen for Sprint 2 as simpler; this is a later evaluation. Relates to the Done/Snooze idea.

## Settings / configurability

- **[P2] Configurable durations via a Settings screen** — cooldown (shipped hardcoded at **1 minute**), probability (shipped hardcoded at **50%**), and, once built, timer duration should become user-configurable via presets + custom (e.g. 5/10/15 min), mirroring the intent-preset UI. Both Sprint 3 triage values are named constants + a `CompositePromptPolicy` so wiring a future presets UI is small, not a rework. See also the "Triage customization UI" item above.
- **[decision] Bubble customization (color/size/opacity)** — deferred correctly: needs (a) a preferences-persistence layer (likely `shared_preferences`, distinct from the `sqflite` intent log) and (b) monetization clarity, since this was a candidate Pro-gated feature and free-vs-Pro is undecided (CLAUDE.md §11). Don't build gating before the model is chosen.

## Exploratory (bigger bets — need scoping before they enter any sprint)

- **[explore] Suggest which app to open** — from the declared intent, surface/deep-link the relevant app (e.g. a payment intent → payments app).
- **[explore] Detect task completion & nudge** — detect whether the user actually opened the relevant app and whether the task seems done, then nudge. **⚠️ Requires `UsageStatsManager` or `AccessibilityService`** — the exact policy-fragile surface CLAUDE.md §9 flags as the single biggest existential risk (prefer UsageStats over Accessibility). Scope the policy risk first.
- **[explore] Launch app directly from the prompt** — tied to the two above; also overlaps the earlier "open apps from the preset" idea. Note the thesis tension: collapsing declare→act into one tap can undercut the deliberate-friction mechanic. Needs deliberate design, not a quick add.
- **[decision] Anonymous opt-in usage tracking** — deliberately deferred, not rejected. Deferred *past the first closed test*, revisited once there are more users than can be talked to individually.
  - **The case for (Dinesh):** this is a consumer app, and self-report is unreliable. Users can't tell you what they don't notice about themselves — which prompts they silently dismiss, where the funnel actually breaks, how behaviour drifts over weeks. Aggregate behavioural data surfaces exactly the things interviews miss, and a wellbeing app whose whole premise is "you don't notice your own phone habits" arguably needs the same honesty about its own usage.
  - **The case against, right now (Claude):** at closed-test scale (~20 named testers) a 15-minute call beats an event stream, costs no engineering, and yields *why* rather than *what*. Analytics is what you build when you can no longer talk to everyone. Building it earlier spends the sprint that could ship the differentiator, and adds real cost: a network dependency in an app that currently has literally zero, a Data Safety form that flips from "no data collected" to a full disclosure (see `docs/PLAY_SUBMISSION.md` §2), a privacy-policy obligation, and erosion of the local-first stance that is currently a genuine differentiator (`CLAUDE.md` §11).
  - **Both are right at different N.** The disagreement is about timing, not principle. Rough trigger: build it when the user base exceeds what one person can interview — order of a few hundred — or when a specific decision is genuinely blocked on behavioural data that no interview can supply.
  - **If/when it's built:** opt-in only (never opt-out), off by default, no third-party SDK if avoidable (a self-hosted endpoint keeps the data genuinely ours), event names reviewed so nothing can reconstruct declared intent *text*, and the Data Safety form updated **in the same release** — not after. Note this reopens the §11 "no analytics or network calls in the free/base experience" principle, so it needs an explicit product call, not a quiet implementation.

---

## Also tracked elsewhere (pointers, not duplicated here)

- **Strategic open decisions** (monetization, branding, iOS, bubble free-vs-Pro, delay-before-unlock): `CLAUDE.md` §11/§12.
- **Sprint 3 as-built design** (storage schema, triage composite, bugs found/fixed): `CLAUDE.md` §3.
- **Known architectural limitations** (OEM kill, process-kill write gap, 3-engine memory): `docs/ARCHITECTURE.md` §6.
- **Plugin + testing gotchas** (shareData fire-and-forget, Android WAL PRAGMA, sqflite widget-test deadlocks, stale Gradle daemons): `docs/ARCHITECTURE.md` §5/§7.
