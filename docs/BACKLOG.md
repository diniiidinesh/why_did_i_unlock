# BACKLOG — Why Did I Unlock

> Deferred engineering/feature work and ideas not yet built. Git-tracked on purpose
> (survives machine switches).
>
> ### CURRENT PRIORITY ORDER (2026-08-15) — set by Dinesh after closed-test feedback
>
> Seven testers gave written feedback (verbatim + triage in
> `docs/erd/onboarding-revamp-2026-08-15.md` Appendix A). Order of work agreed:
>
> 1. **[P0] Onboarding revamp — DONE 2026-08-16.** PRs #20–#23 (copy diet,
>    walkthrough, tooltips + Try it now, day-1 recap) plus **PR #24**
>    (notification tap → same recap screen as icon open). Existing installs
>    are not asked for `POST_NOTIFICATIONS`; they still get the in-app recap.
>    Overlay FGS shade is expected once that permission is granted — Dinesh
>    accepted it (silent, clears on Done). Plan:
>    `docs/erd/onboarding-revamp-2026-08-15.md`.
> 2. **[P0] Outstanding-intent prompt** — plan already written
>    (`docs/erd/outstanding-intent-prompt-2026-08-15.md`), not built. **Promoted
>    on feedback evidence:** Vishishta's "my response isn't recorded and the app
>    doesn't work on subsequent unlocks" and Rohit's "archive the prompt after a
>    few hours" are both this gap. 48 of 109 unlocks in Dinesh's own export were
>    `overlay_active` skips — the app deliberately saying nothing.
> 3. **[P0] Bubble salience regression** — NEW, see the Reliability section below.
>    Two independent testers; goes at the heart of the product thesis.
> 4. **[P1] Insights rework** — Chukka: "insights not visible/helpful, the pie
>    chart isn't that great," "unclear what value the app added." Note the
>    per-app/category breakdown he wants needs `UsageStats` (`CLAUDE.md` §9
>    policy risk) — scope the policy question before the feature.
> 5. **[P1] `maxEnabledPresets` = 8** — the user-interview answer arrived; see
>    the new item under Capture-screen / bubble UX.
> 6. **Then** the pre-existing P1/P2 items below.
>
> The block below is the **superseded** 2026-07-29 state, kept for history.
>
> ### TOP OF NEXT THREAD (2026-07-29) — SUPERSEDED, see above
>
> Merged to `main` (PR #9 Stage B, then PR #8 Beacon rebrand), `0.6.1+9`. Branding,
> privacy, Report a problem, prompt 100%, verb presets, Home load fix, **OEM
> autostart UX + overlay find-hint** are code-complete on `main`. Laptop is back —
> next: **on-device QA + Play Console closed test** (`docs/PLAY_SUBMISSION.md`
> §3–§4).
>
> **Doc-drift note (2026-07-29):** PR #12 ("OEM battery guidance UX") shipped zero
> code — that feature was already merged via PR #8 on 2026-07-25. Its only real
> effect was reverting the "TOP OF NEXT THREAD" block and 3 other doc files back to
> pre-PR-#10 stale phrasing, because it was built from a `cursor/beacon-play-listing`
> checkout that predated PR #10/#11's doc fixes. Reverted here. **Lesson: before any
> session edits CLAUDE.md/README/BACKLOG/PLAY_SUBMISSION, sync the branch to latest
> `main` first** (`git fetch origin main && git merge origin/main` or rebase) —
> otherwise a stale checkout silently undoes doc fixes made after it branched. Added
> to `docs/DOC_UPKEEP.md`.
>
> 1. **On-device matrix** — bubble 54–60, Beacon visual 61–65, verb presets 66–71,
>    Home retry 72, OEM/overlay onboarding 73–76 (`docs/TEST_PLAN.md`).
> 2. **Friend Vivo/Xiaomi soak** — Autostart + No restrictions; leave app closed
>    30–60 min; unlock should still prompt (closes field half of OEM P0).
> 3. **Play gates** — FGS notification on Android 13+; real screenshots; AAB;
>    Data Safety; 12 testers / 14 days if Personal.
> 4. **P0 post-reboot overlay stall** — fix landed; needs verify.
> 5. **After listing exists** — wire `playListingUrl`; privacy effective date.
> 6. **Timer / countdown** — product differentiator; not a listing blocker.
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

- **[P0 → ROOT CAUSE FOUND + fix landed, needs on-device verify 2026-08-15] "Unlock stopped prompting": an unguarded `closeOverlay()` hangs in the overlay isolate, so the pure-Dart `_signalOverlayClosed()` on the very next line never runs and `_overlayIsActive` stays true forever.** This is the actual cause; the two entries below were different failure modes and **neither ever fired** in the field (confirmed: their breadcrumbs/recovery logs are absent from the reports). **Evidence (decisive):** with the app stuck, logcat shows `🔒 Overlay: closing capture screen on lock` printed on two consecutive locks, and `🔵 Overlay closed signal received` never appearing on the background side. Those two log lines sit either side of exactly one statement — `await FlutterOverlayWindow.closeOverlay()` — so the close call never returned. Prior rounds also established the overlay isolate is *alive* (it answered lock signals), which is why the liveness-ping theory was wrong and was dropped before merge: the isolate isn't dead, it's suspended mid-`await`. A hung `await` doesn't block the isolate's event loop, so each later lock re-entered and hung identically — permanent, force-stop the only exit. **Mechanism:** `closeOverlay()` is a plugin call from the OVERLAY isolate, the documented hang hazard in `docs/ARCHITECTURE.md` §5 (`shareData()`'s native handler never replies; `isActive()` hangs below the Dart await). The plugin routes these through one static native field (`WindowSetup.messenger`) owned by whichever engine attached the plugin last, so merely **opening the app** can leave the overlay isolate talking to a detached messenger. All seven `closeOverlay()` call sites were unguarded. **Fix (`lib/main.dart`):** every one now goes through `_closeOverlayWindow()`, which swallows both a hang (via `_withTimeout`) and a throw and always returns, so callers always reach their `_signalOverlayClosed()` / reopen / state reset; emits a breadcrumb when it fires. This also closes the 2026-08-13 fix's blind spot (a hang in `_showBubbleWindow`'s close skipped both the guarded reopen AND `_abandonLostBubble()`). **The durable rule: a pure-Dart state signal must never sit downstream of a plugin call that can hang** — mirrored in `docs/ARCHITECTURE.md` §5. Version `0.6.3+13`. **Verify:** after a lock, `🔵 Overlay closed signal received` must now appear (its absence *was* the bug); if the close still hangs you'll also see `⏱️ closeOverlay(lock) timed out` and the flag must clear anyway ~5s later.

- **[P2 → DONE 2026-08-18, PR #27] `manage_presets_screen_test.dart` "restoring defaults re-seeds the verb five…" flake — two stacked bugs, not one.** Observed 2026-08-15; pre-existing, unrelated to the overlay work that surfaced it. **Bug 1 (the suspected cause, confirmed real):** every widget test across 7 files opened `IntentStore.open(path: inMemoryDatabasePath)` without `ownConnection: true`, so every single one defaulted to sqflite's `singleInstance: true` and shared ONE cached connection keyed by that identical literal path — the desktop-test analogue of the `singleInstance` connection-sharing gotcha in `CLAUDE.md` §3, confirmed this time rather than just suspected. Fixed: `ownConnection: true` on all 9 call sites. **Bug 2 (found after Bug 1's fix still left this one test failing):** separately, this specific test raced a hardcoded 50ms `Future.delayed` against real background-isolate DB I/O (`sqflite_common_ffi` runs on its own Isolate) — fine under light load, not under full-suite CPU contention. Fixed: replaced the blind delay (in this test + the shared `pumpScreen` helper) with a bounded poll (`settle()`) that returns as soon as the UI reflects the change, so it's fast when healthy and only burns the 2s timeout on a genuine regression. Verified with two consecutive full `flutter test` runs, 290/290 both times. **Update 2026-08-18:** the flagged residual risk was real, not theoretical — a follow-up full-suite run failed on exactly one of the five other fixed-50ms spots ("deleting a preset via the confirm dialog removes it from the list"), reproducing the identical flake shape (passed reliably in isolation). Hardened all six remaining occurrences with `settle()`/a new async-aware `settleStore()` variant (for the two assertions that check raw store state rather than widget text). Three consecutive full `flutter test` runs afterward, 290/290 every time — no known fixed-delay races left in this file.

- **[P0 → fix landed, needs final on-device verify 2026-08-13] Sibling of the entry below: `_showBubbleWindow`'s expand/collapse reopen was the one `showOverlay()` call site never ported to the `_withTimeout` guard** — tester reported the bubble vanishing with unlocks silently skipping as `overlay_active` afterward (production build `0.6.2+10`); logcat ruled out an OS/low-memory kill (process + both isolates alive throughout, only kill event was the tester's own later force-stop) and both `_overlayIsActive` (background) and `_mode` (overlay isolate) still believed a bubble was live — pointing at a silent Dart-side reopen failure via the exact same failure class as the entry below, just on a different call site that predates the July fix. Fixed in `lib/main.dart`: `_showBubbleWindow`'s reopen now wrapped in `_withTimeout` + catch, and a new `_abandonLostBubble()` resets `_overlayIsActive`/`_mode` and signals closed on failure instead of leaving the app stuck — deliberately fails open (losing one bubble beats silently killing every future prompt). Audited every other `showOverlay()`/`closeOverlay()` call site in the file for the same gap — none found; this was the only unguarded reopen. Same change adds `ProblemReportLog.recordBreadcrumb()` (see `docs/ARCHITECTURE.md`/`problem_report.dart`) covering unlock outcomes, lock events, and bubble lifecycle including this recovery path, via the existing `intentWritePort` relay for overlay-isolate events. `flutter analyze`/`flutter test` clean (239 tests); Dinesh confirmed normal expand/collapse/rotation on-device 2026-08-13. **Still needs, before release:** a Report-a-problem check with a genuinely fresh (non-stale) log, and ideally a real repro of the original vanish. App is in **Play production** as of 2026-08-13 (not just closed test) — ship as a real version bump (`0.6.3+12`), not folded silently into `0.6.3+11`.

- **[P0 → fix landed, needs on-device verify 2026-07-24] Post-reboot / force-stop-only recovery: hung `showOverlay()` left `_overlayIsActive` stuck true** — After reboot (often with bubble still open), unlocks stopped prompting; opening the app could stick on a loader/blank screen; force-stop + reopen restored normal behavior. Diagnosis (Claude Code, Cursor applied): `showOverlay()` was the one unlock-path plugin call NOT under `_withTimeout`; `_overlayIsActive = true` is set *before* that await, so a never-returning `showOverlay()` made every later unlock silently skip as `overlay_active` until process death. Fix in `lib/main.dart` `_presentCaptureOverlay`: wrap `showOverlay()` in `_withTimeout`, on timeout reset `_overlayIsActive` and log `⏱️ showOverlay() timed out — resetting _overlayIsActive`; unlock logged as `plugin_timeout`. Defensive prefs timeouts also on `AppLauncher._load` + Home load. **Same-day sibling (log-proven):** first post-reboot unlock could show the capture screen with **zero presets** because a timed-out `activePresets()` was sent as `[]` and cached in the overlay — fixed by not sending on null + retries + waiting for a real config reply. **Full RCA (fingerprints, playbook, ruled-outs):** [`docs/debug/rca-post-reboot-overlay-stall-presets-2026-07-24.md`](debug/rca-post-reboot-overlay-stall-presets-2026-07-24.md). **Verify:** reboot with bubble open; expect either normal prompts + presets, or one `⏱️ showOverlay()...` then normal `🎲 Triage: prompting` / `🟣 showOverlay called` on the *next* unlock — no force-stop; never `📤 Sent 0` / `_presets now has 0` immediately after `⏱️ IntentStore.activePresets()`. If stall recurs with **no** `⏱️` line, hypothesis is wrong — reopen investigation. See `docs/ARCHITECTURE.md` §5.

- **[DONE 2026-07-23] Restart monitoring after an app update** — `UpdateReceiver` added, listening for `ACTION_MY_PACKAGE_REPLACED` and restarting `UnlockListenerService`. Found via an on-device build push during Sprint 4: `flutter run` always auto-launches after install, which masked that a real update (Play push, or a manually installed APK) left monitoring dead until the user reopened the app — distinct mechanism from the reboot gap (no "stopped state" involved). Verified on-device (`docs/TEST_PLAN.md` case 45) — **but with an unresolved caveat**: the fix worked reliably once the app had been opened at least once since boot; the very first reinstall attempt on a fully-dormant process produced no trace of the receiver firing at all, not yet explained. Not reproduced a second time, but flagged in case it recurs. See `docs/ARCHITECTURE.md` §2.

- **[DONE 2026-07-22] `android:allowBackup="false"`** — SHIPPED alongside Sprint 3 storage (was unset/defaulting to `true`). Prevents Android auto-backup from sweeping up intent history.
- **[DONE 2026-07-24] T8 — pin `minSdk`/`targetSdk`** — `android/app/build.gradle.kts` previously inherited both from `flutter.*` (resolving to minSdk 24, below the documented API 29 baseline in CLAUDE.md §8 — sideloading hid this). Pinned to `minSdk = 29` / `targetSdk = 36` (sign-off 2026-07-24), full rationale in `docs/PLAY_SUBMISSION.md` §3b.3. **Needs a real on-device pass** confirming the overlay/foreground-service stack is fine at the newly-enforced 29 floor — not yet verified, since this only just started being enforced rather than just documented.
- **[DONE 2026-07-25] OEM autostart onboarding UX** — Was P0 after a Vivo field
  report (prompts silently stop until app reopen). **Not fixable by flipping
  Autostart in code** (no public OEM API). Shipped: manufacturer match
  (`matchOemGuidance` + `device_info_plus`) so Status auto-expands the matching
  tile + “Looks like your phone”; onboarding OEM step shows **full matched
  steps** (or generic fallback); Home dismissible nudge when battery not exempt
  (`AppSettings.oemAutostartNudgeDismissed`); overlay find-hint naming Beacon
  (no auto-advance after grant — user taps Continue). Updated 2026-07-25 for
  field feedback: steps now stress **leave smart/auto optimize**. Vivo path
  confirmed from screenshots (2026-07-25): App info → Battery usage →
  Background power control → **Allow background power usage** (not
  Background power smart control). OnePlus: Battery usage → Optimize battery
  use → Don’t optimize. Battery exemption one-tap was already live. **Still
  needs friend soak verify** (TEST_PLAN 76–77).
- **[DONE 2026-07-21] `LOCKED_BOOT_COMPLETED` (direct boot)** — SHIPPED. `BootReceiver` + `UnlockListenerService` are now `directBootAware` and handle `LOCKED_BOOT_COMPLETED`, so monitoring starts before the first post-reboot unlock. Verified across 2 real reboots (prompt appeared ~2s after boot, zero manual app-open). The device-encrypted-storage concern turned out moot: our logic only runs on `ACTION_USER_PRESENT`, which fires after unlock when normal storage is already available.
- **[P2] Graceful degradation when overlay permission is denied/revoked** — currently a silent no-op (confirmed). CLAUDE.md §8 calls for a notification-based fallback instead. Not built.
- **[DONE 2026-07-24] HomeScreen was never wired to the screens Cursor already built** — `about_screen.dart`, `status_screen.dart`, `manage_presets_screen.dart` existed as unreachable files (no task in the Sprint 4 plan explicitly owned "link Home to them"); `onboarding_screen.dart` existed but `MyApp` went straight to `HomeScreen`, so nobody ever saw onboarding and the cold permission-request in `HomeScreen.initState` was still live. Fixed: `MyApp` now routes through a new `AppLauncher` (checks `AppSettings.onboardingCompleted()`, shows `OnboardingScreen` or `HomeScreen`); `HomeScreen`'s cold `_requestOverlayPermission()` call removed (onboarding's own permission step replaces it); `HomeScreen` now links to Manage presets/Status/About alongside History. `flutter test` and `flutter analyze` clean.
- **[DONE 2026-07-24] Status screen "ignore battery optimizations" one-tap dialog** — added via `permission_handler` (`Permission.ignoreBatteryOptimizations`), distinct from the OEM-specific Autostart Manager screens (Vivo/Xiaomi/Oppo), which have no public API and stay instructions-only (`oem_autostart_copy.dart`, already live). New manifest permission `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` — flagged for Play review attention in `docs/PLAY_SUBMISSION.md`.
- **[DONE 2026-07-24] T14 — insight queries** — `IntentStore` gains `unlockCount`/`promptShownCount` (windowed today/7d/30d), `outcomeBreakdown` (plain counts per `OutcomeCategory`, feeding T18's `DonutSlice`s), and `completionDurationStats` (SQL-computed median + mean, per docs/DATA_MODEL.md §8's "COUNT then ORDER BY...LIMIT 1 OFFSET n/2" decision). All windowed and index-backed (`idx_unlocked_at`/`idx_declared_at`), never full-table scans. **Known simplification, flagged not solved:** duration stats don't exclude intents whose open period spanned a screen-off, since there's no persisted lock-event table to detect that from — `onLock` is still debugPrint-only. T18 (Cursor) can now build the Home cards/donut against this API.
- **[DONE 2026-07-24] T17 — CSV export** — `IntentStore.exportRows()` (unlocks LEFT JOIN intent/preset, then orphan intents), `lib/export_csv.dart` (RFC4180 + ISO-8601 local), Settings/Your-data "Export data" via `share_plus`. Automated: `test/export_csv_test.dart` + store export cases. Needs on-device share-sheet smoke.
- **[DONE 2026-07-24] T18 — Home insight cards + Your data** — `lib/home_screen.dart` (status, today/7d/30d counts, outcome donut, duration stats, settings summary, nav); Settings `YourDataCard` (counts, oldest, retention chips, export, delete-all keeping presets, delete-older-than); store helpers `userDataCounts`/`oldestRecordAt`/`deleteAllUserData`/`pruneOlderThan`. Automated: `test/home_screen_test.dart` + settings Your-data cases. Opportunistic foreground prune still deferred.

### Home insights / Settings follow-ups (post-T18)

- **[P1 — NEW 2026-08-15] Insights aren't landing.** Chukka: *"Insights are not
  visible/helpful; the pie chart isn't that great… no clear breakdown that can help
  me change behaviour,"* and *"unclear what value [is] added by the app."*
  Two separable problems: (a) the existing donut/duration presentation isn't
  legible or actionable — addressable today with no new permissions; (b) the
  breakdown he actually wants is **per-app / per-category** ("Social media, which
  includes Twitter, Instagram") which needs `UsageStatsManager` — `CLAUDE.md` §9
  policy risk, and a departure from the local-only, self-declared data model.
  **Do (a) first; (b) needs a product+policy call, not just engineering.** The
  day-1 stats screen in `docs/erd/onboarding-revamp-2026-08-15.md` §4C.5 is a
  partial down-payment on (a).

- **[P2 — DONE 2026-08-16] Rename the "Time to mark done" insight label.**
  Vishishta: *"I am not clear what the 'Time to mark done' feature means."* It's a
  duration statistic, not a feature, and the label reads like a setting. One-line
  copy fix — Home now says **"How long until Done"** (`cursor/onboarding-tooltips`).

- **[P2] Outcome donut — prompt-level (per-preset) breakdown** — today's donut is outcome categories only (`IntentStore.outcomeBreakdown` → T15/T18). Want a split of **which presets** contributed inside a slice (e.g. within "done", how many were Payments vs Calls). A full dedicated per-preset breakdown screen is optional later; **MVP:** tap/long-press (or hover on desktop) a slice → tooltip/sheet showing preset-level counts for that outcome. Needs a store query that groups by `(outcome category, preset_id/label)` for the active insight window — not just category totals. Requested 2026-07-24.

- **[P2] Multiple quiet-hours windows** — `AppSettings.quietHoursWindow` + Settings UI + `QuietHoursPolicy` + `docs/DATA_MODEL.md` §11 today hold a **single** start/end pair. Supporting several windows (e.g. nap + overnight) needs a settings schema change to a **list** of windows (not one pair), Settings UI to add/remove/edit windows, and policy logic that suppresses if *any* window contains `now` (including each window's midnight wrap). No `intent_log` migration — prefs/settings only — but treat as a real settings-format bump with a migration from the single-window shape. Requested 2026-07-24.

- **[explore] Home insight window: calendar days and ISO weeks** — today the Home chips are rolling `today` / `7d` / `30d`. Request: also let the user toggle **calendar days** (already how "today" works; extend to pick N days or a day picker) and **ISO weeks** as bucketing. ISO week grouping is **new** logic across `IntentStore.unlockCount` / `promptShownCount` / `outcomeBreakdown` / `completionDurationStats` (and Home UI), not a trivial chip rename — don't start until it's clear this is worth the complexity over the existing rolling 7d/30d windows. Requested 2026-07-24.

## Storage / history (Sprint 3 — DONE)

- **[DONE 2026-07-22] Overlay write path, IsolateNameServer relay, and concurrent-open guard** — Bugs 1–4 found and fixed (see summary above). Write path now reliably delivers every event across multiple dismiss cycles, even after swipe-away and reboot. Verified end-to-end with 27 automated tests + 24 manual on-device cases.
- **[DONE 2026-07-22] Prompt-frequency triage** — cooldown (1 min) + probability (50%) composite, both verified working correctly against real event data. Triage gate plugs into `_showCaptureScreen`, inputs validated fresh per unlock.
- **[FIXED 2026-07-24, needs on-device re-verify] A manually-triggered test answer ("Show me the prompt now") applies real cooldown to the NEXT REAL unlock.** Confirmed on-device 2026-07-24:
  ```
  🟣 showOverlay called (1080x2400 capture screen)
  🧪 Manual prompt shown (Status screen trigger)
  🤷 No intent declared ("Just Like That") at 2026-07-24 01:10:54.643686
  💾 Stored no-intent event: text="Just Like That"
  🔒 LOCK EVENT RECEIVED at 2026-07-24 01:10:56.397106
  🔓 UNLOCK EVENT RECEIVED at 2026-07-24 01:10:58.199707
  🎲 Triage: skipping — COOLDOWN active (elapsed 0:00:03.556781 < 0:01:00.000000)
  ```
  **Root cause:** `_showCaptureScreenManually` (the Status screen's "Show me the prompt now"
  button, T6) already deliberately skips `_logUnlock` for itself, specifically so a manual
  test "would inflate 'unlocks today' and the prompt-rate stats with test-only noise the
  metrics were never meant to include" (see that function's doc comment in `lib/main.dart`).
  But the SAME protection was never extended to what the user answers on that manually-shown
  screen: `_submitIntent`/`_submitNoIntent` relay to `IntentStore.insertOpenIntent`/
  `insertEvent` unconditionally, with no way to tell "this answer came from a real unlock"
  apart from "this answer came from a manual test tap." `TimeCooldownPolicy` reads
  `IntentStore.lastCompletedAt()` — `MAX(completed_at)` across ALL `intent_log` rows,
  manual-origin or not (docs/DATA_MODEL.md §4 explains why it deliberately includes `open`/
  `abandoned` rows, but says nothing about EXCLUDING manual-test rows, because the concept
  of "manual-test row" doesn't exist in the schema at all). Net effect: tapping the test
  button and answering it silently arms the cooldown for the next several real unlocks —
  exactly the confusing "why didn't it prompt me, is the trigger broken?" symptom a tester
  would see, when the trigger itself worked perfectly.
  **Fix shipped (`lib/main.dart`, `cursor/sprint4-stage-b`):** direction 2 — don't persist
  manual-trigger answers to `intent_log` at all, mirroring `_showCaptureScreenManually`'s
  existing `unlock_log` exclusion. The overlay isolate previously had no way to tell a real
  unlock from a manual trigger on its own (both take the exact same `showOverlay()` code
  path via `_presentCaptureOverlay`), so this needed a new signal, not just a background-side
  filter: a module-level `_currentPresentIsManual` flag is set synchronously in
  `_presentCaptureOverlay` (before `showOverlay()`, same "set before the await" rule as
  `_overlayIsActive`) and piggybacked on the SAME preset-push/reply message the [P0] fix
  above already sends (`{'presets': [...], 'manual': true/false}` over
  `_overlayConfigPortName` — one message, not two, since a second presets-less message on
  that port would be misread as "zero active presets"). The overlay stores it as
  `_sessionIsManual` and checks it in `_submitIntent`/`_submitNoIntent`/`_dismissBubble`,
  skipping only the `_relayDeclaredIntent`/`_relayNoIntent`/`_relayDismissal` DB-write calls
  — the bubble/close/UI transitions all still happen exactly as before, so a manual session
  still looks and behaves identically to a real one for whoever is testing it, it just leaves
  no `intent_log` row. Rejected **direction 1 (tag-and-filter)**: no schema/migration needed
  for direction 2, and the manual trigger's real purpose (verifying the write path end-to-end,
  per Sprint 3's history) is still fully exercisable by watching `debugPrint` output
  (`🧪 Manual session — skipping intent_log ... write`) and the resulting bubble/UI, without
  needing a persisted row to prove the path worked.
  Not fixed here — flagging with full repro + root cause so it doesn't need re-diagnosing.
- **[DONE 2026-07-22] Minimal history view** — `lib/history_screen.dart` reads from the DB, renders events newest-first, styles no-intent rows distinctly. Verified against real multi-event data on-device.
- ~~**[P2] Triage customization UI**~~ — done via T13 (`lib/settings_screen.dart`): cooldown/probability are curated preset chips + a validated Custom entry, not the originally-imagined sliders (see that screen's doc comments for why). Instance-based triage strategy (e.g. "skip every Nth unlock") is still not built — see the `[explore]` item below.
  - **Probability options:** Everytime (100%, **current default as of 2026-07-25**), 75%, 50%, 25%, Never (0%) — or custom percentage input. (Old Sprint 3 default was 50%; changed after friend confusion.)
  - **Cooldown options:** No cooldown (0 min), 1 min (current default — kept; explained in onboarding/Settings), 2 min, 5 min, 10 min — or custom duration input.
- **[explore] Instance-based triage strategy** (e.g. "skip every Nth unlock") — a third `PromptPolicy` implementation alongside cooldown/probability; same architecture, not yet built.
- **[P2] `status` (completed-vs-abandoned) on `intent_log`** — deferred until the UI actually supports more than one dismiss gesture (still just the × badge).

## Performance (must run on low-end devices — CLAUDE.md §8)

- **[P2 — NEW 2026-08-18] Play Console flagged R8 optimization is incomplete.** Dashboard's "Protected with Play" panel: "Optimized resource shrinking isn't enabled" + "Upgrade your Android Gradle plugin to version 9.0 or higher," surfaced against the `0.6.4 (14)` production bundle. Distinct from the already-tracked R8-mapping-file gap in `docs/PLAY_SUBMISSION.md` §4 (that one is about crash-report *readability*; this one is build-config leanness — install size / memory / a bit of performance, in keeping with CLAUDE.md §8's low-end-device requirement). Two real changes implied: (1) an explicit `shrinkResources`/optimized-R8-mode setting in `android/app/build.gradle.kts` (currently R8 runs only because the Flutter Gradle plugin defaults it on, nothing explicit configured — CLAUDE.md §2); (2) an AGP major-version bump in `android/settings.gradle.kts`/`android/build.gradle.kts`. **Deliberately parked, not rejected** — (2) is a native-build-file change (CLAUDE.md §7: ask-first territory) with a real history of breaking Gradle builds on major bumps, and right after the first production release is a bad time to absorb unrelated toolchain risk for a leanness nudge rather than a functional bug or Play-policy blocker. Revisit as its own careful, ask-first change, not bundled into an unrelated PR.
- **[P2] Overlay engine pre-warm** — first capture screen after unlock is slow (cold-starts the overlay's second Flutter engine); the dismiss close+reopen adds a native round-trip. Investigate pre-warming at app start. Ties to the ~500ms unlock-path target.
- **[P2] Untested surfaces** — landscape/rotation (capture screen + pill), low-end-device pass (≤3GB, older Android — only tested on a modern Nothing Phone so far), battery soak vs. the <2%/day target.
- **[P2] Overlay engine cold-start latency** — the overlay's second Flutter engine spins up on each `showOverlay()` call, adding observable (device-dependent, but ~1–2s on some runs per on-device tests 2026-07-22) latency between unlock→capture-screen-visible. Pre-warming the overlay engine at app startup (best-effort, non-blocking) could eliminate that. Known architectural limitation (CLAUDE.md §8); deferred to Sprint 4 since the core functionality works, just slowly.
- **[DONE 2026-07-23] Config-relay (T11) pills consistently missing — root-caused and fixed.** The overlay-side logging added to diagnose this (previous entry) caught it on the very next reproduction: `initState` registered its port and sent `requestPresets` at 23:07:56.469, but background's `_intentWritePortName` port wasn't registered yet (`⚠️ Could not find intent-write port — background engine not ready?`) — a real, if brief, startup race (background was very likely mid-restart at that exact moment). Because `_requestPresets()` only ever fired once per cached overlay engine's lifetime with no retry, that single failed attempt was **permanent** for the rest of that engine's life: a completely normal unlock 13 seconds later (`🔓 UNLOCK EVENT RECEIVED` → `🟣 showOverlay called`) reused the same cached, still-empty `_presets` — not a fluke, a standing failure until the whole process restarted. Fix (`lib/main.dart`): `_requestPresets` now retries up to 5× with a 400ms delay (~2s total window) before giving up, and `_sendToBackground` now returns `bool` so the retry loop can tell success from failure. Same underlying lesson as the `triggerCapturePromptManually` fix earlier this session — fire-and-forget across this isolate boundary needs either a retry or an honest failure signal, silent-void is never safe here. **Re-verified on-device 2026-07-23** — pills now appear reliably after the retry fix.
- **[FIXED 2026-07-24, needs on-device re-verify] `_presets` on the overlay engine goes stale for an entire session — a NEW bug, distinct from the config-relay race above.** Confirmed on-device 2026-07-24, two separate reports that are the SAME root cause:
  1. A newly-created preset ("Testing") didn't appear on the very next real unlock's capture screen, but did appear "on the second unlock or after reopening the app."
  2. After reordering and deactivating presets in Manage Options, **no real unlock reflected the change at all** — not on the next unlock, not after reopening the app, not after several more unlocks — **until the device was rebooted**, at which point the change finally showed up.

  **Root cause:** `_requestPresets()` (`lib/main.dart`, `_OverlayRootState`) is only ever called from two places: `initState` (the overlay engine's cold start) and the end of `_dismissBubble()` (after a bubble is dismissed, resetting back to capture mode). It is **not** called after `_submitNoIntent()` ("Just Like That" — that path resets nothing, per its own doc comment, "state is already clean for the next unlock"), and it is **not** called on every fresh capture-screen show from a real unlock — only capture→bubble→capture transitions trigger a refresh.

  So: the overlay engine is a long-lived CACHED process (`docs/ARCHITECTURE.md` §1/§5 — it survives `closeOverlay()`/`showOverlay()` cycles and is only ever destroyed by a full process kill). If a user's unlocks during a session are ever answered via "Just Like That" (no bubble, no dismiss, no re-request) — or if the overlay engine simply hasn't gone through a capture→bubble→dismiss cycle since the preset edit — `_presets` sits at whatever it was when `initState` last ran, for the **entire remaining life of that cached engine**, regardless of how many real unlocks happen or how many times the main UI app is reopened (reopening the main UI engine doesn't touch the overlay engine at all — they're separate engines, `docs/ARCHITECTURE.md` §1). A device reboot is the only thing that reliably clears this, because it's the only thing that kills the cached overlay engine and forces a fresh `initState` → `_requestPresets()` call.

  This also explains "the ordering isn't working, the new option added at the end" — the visible pill order is whatever stale `_presets` list was last fetched; a newly-created preset was never fetched at all, so nothing about its position is meaningful yet either.

  **Fix shipped (`lib/main.dart`, `cursor/sprint4-stage-b`):** a variant of option 1 above, but hooked at the right shared choke point instead of "every real unlock" literally. The overlay isolate never sees unlocks directly — both the real-unlock path (`_showCaptureScreen`) and the manual Status trigger (`_showCaptureScreenManually`) already funnel through one shared function, `_presentCaptureOverlay`, for the actual `showOverlay()` call. That function now also pushes a fresh `_replyActivePresetsToOverlay(store)` call immediately after `showOverlay()`, fire-and-forget (`unawaited`, not blocking the ~500ms unlock path, matching how `_logUnlock` already runs after rather than before `showOverlay()`). This covers **every** capture presentation — cold overlay start, a long-cached engine reused after any number of "Just Like That" answers, after a lock-close, after Manage Options edits made while the overlay was closed — not just the answer-triggered paths (`_dismissBubble`'s existing `_requestPresets()` call stays as an extra, now-redundant safety net). On a genuinely cold overlay engine start the push can still land before `_overlayConfigPortName` is registered and get dropped — that's fine, because the overlay's own `initState` → `_requestPresets()` pull (with its existing bounded retry) is what reliably covers that specific case; the two mechanisms are complementary, not redundant, for different scenarios. Rejected: **option 2 (push-invalidation from Manage Options)** alone, because it doesn't fix "Just Like That"-only sessions where nothing ever mutates presets but the engine still never refreshed after being cached; **option 3 (staleness window)**, because it adds complexity for no benefit once option 1 is correctly hooked. **Needs an on-device re-run of the original repro** (create/reorder/disable presets in Manage Options, unlock without reboot; several "Just Like That" answers, then edit presets, then unlock) before this can be marked fully `[DONE]`.
- **[P2] Show a max-presets counter (e.g. "5/8 enabled") in Manage Options.** `maxEnabledPresets`/`maxStoredPresets` already exist as constants in `lib/intent_store.dart`; this is purely a UI addition — a `Text` showing `${enabledCount}/$maxEnabledPresets` near the top of the list. Requested 2026-07-24 so users understand the cap before hitting `PresetLimitExceeded`, rather than only discovering it via an error.

## Capture-screen / bubble UX

- **[P0 — NEW 2026-08-15] Bubble salience regression: the amber bubble is being
  tuned out.** Two independent closed testers, same complaint. Sanchary: *"the
  beacon has become easier to ignore now… before I would still have the awareness
  of the purple thing in my peripheral vision. Now the orange thing is almost
  blending into the… I am just not noticing it."* Omkar, independently, asked for
  the bubble to **move to a random location and change colour** ("animate into a
  nice random pokemon") for exactly the same reason — he describes suppressing
  calendar reminders blindly as muscle memory: *"Operation successful but Patient
  dead."*
  **Likely cause:** the 2026-08-11 batch-2 change that clipped `_BeaconGlassShell`
  to its exact shape (`ClipRRect`) and removed the `amberGlow`/`BoxShadow` token.
  That fix was correct on its own terms — the glow was rendering as a flat
  amber-tinted square because the native overlay window has zero margin for the
  blur to fade — but it removed *salience* along with the artefact, and the
  Beacon amber is lower-contrast against typical app backgrounds than the old
  purple was.
  **Why this is P0, not polish:** `CLAUDE.md` §10 puts the bubble at the centre of
  the product thesis (the prompt alone is explicitly *not* the differentiator). A
  bubble that gets tuned out is the whole product getting tuned out — Chukka's
  *"the bubble actually helped me remember why I opened the phone only once in the
  past ten days"* is the same failure measured differently.
  **Options to scope (not yet decided):** restore a correctly-clipped halo by
  sizing the overlay window with margin for the blur; periodic subtle motion or a
  slow pulse (must respect `CLAUDE.md` §8 — no continuous animation in the overlay
  engine, so any motion needs to be occasional and cheap); position drift over
  time; colour shift as the intent ages (ties naturally to the unbuilt timer).
  Needs a design call before building.

- **[P1 — NEW 2026-08-15] `maxEnabledPresets = 8` — the user-interview answer
  arrived.** Chukka: *"8 options feels like a limitation… it'll be helpful if more
  options are present."* `CLAUDE.md` §12 / batch 2 recorded the cap as staying at 8
  "pending a real user-interview answer" (`docs/USER_INTERVIEWS.md`). This is that
  answer — one data point, not a mandate, but the question is no longer
  unanswered. Counter-consideration: more pills on the capture screen fights the
  fast-unlock-path and thumb-zone work, so raising the cap is not free. Record the
  data point in `docs/USER_INTERVIEWS.md` either way.

- **[P2 — NEW 2026-08-15] Save a typed custom intent as a reusable preset.**
  Devansh: *"The prompts given manually on screen, is there a way to store them and
  show them?"* Natural fit with Manage options and the parked suggestion catalog
  below. Interacts with `maxEnabledPresets` (above) — a one-tap "save this" that
  silently hits the cap would be a bad first experience, so scope the cap question
  first.

- **[explore — NEW 2026-08-15] Prompt on task deviation.** Rohit: *"If the user is
  done with the task or gets diverted into another task, should we prompt the user
  regarding the deviation?"* ⚠️ Detecting "diverted into another task" requires
  `UsageStatsManager` or `AccessibilityService` — the exact policy-fragile surface
  `CLAUDE.md` §9 flags as the single biggest existential risk. Same dependency as
  the existing "[explore] Detect task completion & nudge" item. Scope the policy
  question once, for both.

- **[DONE 2026-07-21] "OK"/submit button** — SHIPPED next to the text field.
- **[DONE 2026-07-21] "Just Like That" option** — SHIPPED (logs a purposeless unlock, closes without a bubble). Styling follow-up is item #2 at top of file.
- **[DONE 2026-07-21] Prompt on/off master toggle** — SHIPPED (HomeScreen switch, `shared_preferences`, `_shouldPrompt()` gate). Scheduling to plug into that same gate is a future item; see `CLAUDE.md` §3-adjacent notes.
- **[DONE 2026-07-21] Meaningful presets** — Payments/Calls/Messages/Food Order/Commute replaced the vague originals.
- **[DONE 2026-07-25] Verb-based defaults for job-goer TG** — Enabled five: Check mail / Message someone / Book a cab / Order food / **Pay someone** (Watch reels moved to suggestion catalog). Seed v3 migrates untouched legacy + untouched v2 verb installs; **customized lists are left alone** (observed: install with custom “Testing” correctly skipped auto-migrate — Restore defaults / clear data is the escape hatch). Spec: `docs/erd/verb-presets-job-goers-2026-07-25.md`. **Needs on-device** TEST_PLAN 66–71.
- **[DONE 2026-07-25] Prompt default probability → 100%** — Friend testing read 50% skips as “broken.” Default is now ask every unlock once the 1-min cooldown clears; Settings still tunable; onboarding + Settings subtitles explain. (`AppSettings`, `OnboardingScreen`, `SettingsScreen`, Home summary always shows `$pct%`.)
- **[DONE 2026-07-25] Home insight Mean row restored + orphan “More” heading removed** — Mean under Median again; History/Manage/About links no longer under a bare “More” label.
- **[DONE 2026-07-25] Home “Couldn't load local data” / pull-to-retry** — Cold load no longer closes an opened store after a permission/settings timeout; pull-to-refresh re-runs full `_load()` when `_store == null` (was a no-op). Failures `debugPrint` as `🏠 Home._load failed: …`. **Needs on-device** TEST_PLAN 72.
- **[explore] Onboarding preset picker (“pick ~5–8”)** — Parked 2026-07-25. Cold users can’t predict unlock mix; onboarding is already permission-heavy. Revisit after closed-test usage patterns, as “confirm suggestions” not “design from scratch.”
- **[explore] Suggestion catalog (inactive / Add from list) in Manage Options** — Parked 2026-07-25. Candidates: Call someone, Set alarm, Reply to someone, Watch reels, Get directions, Check social media. Seed as soft suggestions without crowding the capture screen. Enable/disable already exists; this is curated inventory + UX.
- **[explore] Second no-bubble escape (“in a rush” / urgent skip)** — Parked 2026-07-25 / rejected for now. Same motor outcome as Just Like That, pollutes `no_intent`, trains skip-when-busy. Prefer verb coverage + later voice.
- **[DONE 2026-07-21] Capture-screen keyboard handling revamp** — The interim v0.4.0 fix just shifted the whole column up, pushing presets off-screen. Now uses thumb-zone layout: title/presets/"Just Like That" bottom-anchor within scrollable space (LayoutBuilder + ConstrainedBox + IntrinsicHeight + mainAxisAlignment.end), text field pinned as footer just above keyboard. In PR #6, pending merge.
- **[DONE 2026-07-21] "Just Like That" pill styling** — Was a bare italic `TextButton`; now a real outlined pill (muted relative to topic presets so it still reads as the distinct "no real reason" option). In PR #6, pending merge.
- **[explore] Randomize preset pill order** — Presets appear in fixed order every unlock; muscle-memory tapping ("I always hit the second pill because it's Calls") is low-deliberation behavior. Prompt-timing randomization (shipped via probability gate) fights habituation by making timing unpredictable, which the research shows is neurologically effective and harmless. Position-randomization fights muscle memory but risks backfire: if pills are hard to locate, users might skip thinking and just hit "Just Like That" from friction rather than honesty — fixing one habituation by inducing another. Only builds if position-randomness is bounded (shuffle within session? vary per boot?) not truly random per-unlock. Needs UX evaluation first.
- **[DONE 2026-07-24] Drag / edge-snap behavior** — Bubble uses `PositionGravity.none`
  + background `_snapBubbleToEdge` (plugin `auto` caches screen size once and
  snaps mid-landscape after rotate). Expand while left-docked also re-snaps so
  the pill stays fully on-screen. Half-peek Messenger dock still optional.
- **[DONE 2026-07-24] Bubble survives screen rotation** — Native
  `UnlockListenerService.onConfigurationChanged` → `onOrientationChanged`
  `{width,height}` (same `ScreenMetrics` as unlock) → background **one**
  close+reopen. Overlay Dart metrics path removed. Snap uses last native
  W×H÷dpr (not overlay `displays`). **On-device:** cases 57/59/60 exercised
  (expect `📐 ORIENTATION EVENT` then `📐 Orientation: one bubble reopen…` —
  not `📌` spam; landscape left snap `screen≈914…` not `x=359`). Reconfirm
  after Beacon theme change.
- **[DONE 2026-07-24] Adaptive bubble sizing** — Expanded width hugs text up to 240dp (`lib/bubble_widget.dart`).
- **[DONE 2026-07-24] Smaller footprint + richer actions** — Collapsed 52dp chat-head; Expanded has **Done** (tick) + **Snooze** (temporary hide, unlock ends early). Plan: `docs/erd/bubble-ux-hybrid-plan-2026-07-24.md`.
- **[DONE 2026-07-24] Icon + tap-to-expand hybrid bubble** — Confirm-then-collapse (1C): declare opens Expanded, auto-collapses ~2s; tap toggles. Material icons per preset; letter avatar for custom.
- **[DONE 2026-07-24] Beacon visual identity** — Replaced purple `#6200EE` with amber
  `#FFB300` + frosted glass (`lib/beacon_theme.dart` → `beaconDarkTheme()` on main UI
  + overlay). Bubble: black@60% + backdrop blur + amber border/glow + white glyphs.
  Also: Settings switches, Manage FAB, Home donut “Done” / window chips, unlock
  preset outlines. Spec: `docs/erd/beacon-visual-identity-2026-07-24.md`. Automated:
  `test/beacon_theme_test.dart`. **Needs on-device visual pass** (TEST_PLAN 61–65).
  Store brand **decided** (`Beacon: Mindful Phone Use` / on-device `Beacon`) —
  see `CLAUDE.md` §12 and `docs/PLAY_SUBMISSION.md` §0.

## Settings / configurability

- **[DONE 2026-07-24] T13 — Settings screen** — `lib/settings_screen.dart` (Cursor), merged into `sprint4-app-shell` and wired into `HomeScreen`'s nav (Cursor's commit left it self-contained/unwired; Claude Code added the link). Prompts on/off, cooldown/probability as curated preset chips + validated Custom entry (clamped, with a SnackBar on out-of-range input — defense in depth on top of `AppSettings`'s own clamping), quiet-hours toggle + time pickers, links to Manage options and the privacy policy. Supersedes the item below.
- **[decision 2026-07-25] Delay-before-unlock — no Settings “Coming soon” row.** Idea remains open/unscoped (`CLAUDE.md` §12). A dead Settings control creates expectation debt and looks broken in closed test; ship a real toggle only after bypass list + schedule + prompt interaction are designed.
- ~~**[P2] Configurable durations via a Settings screen**~~ — done via T13 above. Timer duration isn't configurable yet since the timer feature itself doesn't exist (`CLAUDE.md` §3/§10) — revisit when it ships.
- **[decision] Bubble customization (color/size/opacity)** — deferred correctly: needs (a) a preferences-persistence layer (likely `shared_preferences`, distinct from the `sqflite` intent log) and (b) monetization clarity, since this was a candidate Pro-gated feature and free-vs-Pro is undecided (CLAUDE.md §11). Don't build gating before the model is chosen.

## T6 "no prompt at all" investigation (2026-07-23) — likely resolved, needs one confirmation

Cursor reported "Show me the prompt now" doing nothing, and a **real unlock also not
showing the capture screen** on the same test run. Root cause is very likely a tooling
artifact, not a `backgroundMain`/`main.dart` regression: Cursor tested via a throwaway
`tool/preview_screens.dart` harness (`flutter run -t tool/preview_screens.dart`, debug),
not the real `lib/main.dart` entrypoint. `backgroundMain()`/`overlayMain()` are
`@pragma("vm:entry-point")`, which only preserves + registers them as natively-invokable
entry points if they're reachable from **whichever file the compiler was told is the
entrypoint** — `tool/preview_screens.dart` almost certainly doesn't import `lib/main.dart`,
so that build's Dart bundle never contained `backgroundMain` at all, explaining every
symptom (service alive but `backgroundMain ready` never logged, all
`IsolateNameServer` lookups returning null, manual trigger and real unlocks both silently
doing nothing) as one cause, not several.

- **[P0] Confirm on the real entrypoint** — `flutter run --release -d <device>`, default
  `lib/main.dart`, no `-t`. If the capture screen still doesn't appear on a real unlock
  here, this is a genuine regression needing real investigation, not a tooling artifact —
  escalate immediately. If it works normally, the diagnosis above is confirmed and this
  item closes.
- **[DONE 2026-07-23] `tool/preview_screens.dart` warning** — Header doc comment states
  this is a separate entrypoint without `backgroundMain`/`overlayMain`; safe for
  pure-UI previews only. Also wired to `beaconDarkTheme()` (2026-07-24) so Manage FAB
  / switches match production accents during harness QA.
- **[DONE 2026-07-23]** `triggerCapturePromptManually()` now returns `bool` (was `void`) —
  `false` when the background engine's port can't be found, so the Status screen can show
  an honest "background engine not reachable" instead of always implying success. See
  `lib/main.dart` doc comment and `docs/ARCHITECTURE.md` §3. Cursor can now wire this into
  `status_screen.dart`'s UI (currently ignores the return value, per its `void`-typed
  `ManualPromptTrigger` — Dart allows this, no compile break, but the richer signal is
  unused until Status reads it).

## Docs housekeeping (assessed 2026-07-23)

- **[P2] `TEST_PLAN.md` case numbering is fragmented** — 1–9, 5e/5f/5g sub-cases, 10–12, 13–18, 20–27, 30–35, 40–42, 45–58, grown organically across sub-sections. Not broken, just hard to scan. A renumbering pass is possible but risks breaking hand-written cross-references elsewhere — needs care, not urgency. **Still open.**
- **[P2] `ARCHITECTURE.md` §3 (Channels)** has grown into a long nested bullet list (five `IsolateNameServer` ports now, each a paragraph) — consider a table like §2 already uses, for scannability. **Still open.**
- **[DONE 2026-07-23] `README.md` doc-map audit** — real gaps found and fixed: `docs/DATA_MODEL.md` had **no row at all** despite being one of the most-referenced docs; `docs/PRIVACY_POLICY.md` and `docs/debug/` were also missing. The `docs/erd/` row's description was stale too (said "not updated after sign-off," contradicting the update-log policy actually adopted). All fixed in one pass.
- **[DONE 2026-07-23] `DATA_MODEL.md` §11/§12 numbering** — checked, sequential 1–12, stayed correct since the earlier fix.

## Store listing / About follow-ups (Play)

- **[DONE 2026-08-16] Privacy policy effective date + hosted sync** — effective
  date has been real (**25 July 2026**) since the listing went up; the item was
  just never closed. Hosted page at `dineshkaliki.com/beacon/privacy/` re-synced
  2026-08-16 to add the `POST_NOTIFICATIONS` bullet shipped with the day-1
  recap. **Gotcha for the next sync:** the live page (served from
  `diniiidinesh/dineshkaliki.github.io`, path `beacon/privacy/index.html`,
  `CNAME` → `dineshkaliki.com`) carries a **Cloudflare Web Analytics snippet in
  `<head>` that `docs/site/privacy.html` does not**. Copying the mirror over the
  live file wholesale silently deletes it — merge the policy change into the
  live file instead, or re-add the snippet. Note also `diniiidinesh/beacon-site`
  exists with a similar tree but is **not** what serves the domain; don't edit it
  by mistake.

- **[P1] Wire About "Rate on Play" + "Share" to the real listing** — today both
  open `playListingUrl` which is still a `TODO_*` placeholder
  (`lib/brand.dart`). After the Play listing exists: set
  `https://play.google.com/store/apps/details?id=com.whydidiunlock.why_did_i_unlock`,
  confirm Rate opens the store, and make Share use the system share sheet
  (`share_plus` already in the tree for CSV) with that URL + short pitch.
  Until then the buttons correctly SnackBar "not on Play yet."

- **[DONE 2026-07-25] FGS notification small icon → Beacon** —
  `drawable/ic_stat_beacon.xml` (white silhouette) +
  `UnlockListenerService` `.setSmallIcon(R.drawable.ic_stat_beacon)`; channel
  renamed/id bumped to `beacon_monitoring` / display name "Beacon".

- **[DONE 2026-08-18] Day-1 recap notification was showing Android's stock icon, not Beacon.**
  `DayOneNotifications.initialize()` (`lib/day_one_notifications.dart`) passed
  `AndroidInitializationSettings('@mipmap/ic_launcher')` — but `ic_launcher` is
  an **adaptive icon** (`mipmap-anydpi-v26/ic_launcher.xml`, background +
  foreground layers), which Android can't render as a status-bar/notification
  icon (must be a flat white silhouette on transparent, no color/gradient).
  Android silently fell back to its own default icon instead of erroring.
  Fixed by pointing at the same status-bar-safe asset the FGS notification
  above already uses — `AndroidInitializationSettings('ic_stat_beacon')`
  (`res/drawable/ic_stat_beacon.xml`, resolved by resource name, no `@mipmap/`
  prefix). No native/Kotlin change needed — the asset already existed. Both
  Beacon notifications (persistent monitoring + day-1 recap) now share one
  small icon.

- **[DONE 2026-07-25] "Report a problem" mailto + local error buffer** — About
  → Report a problem emails `hi@…` with version/OS, a "what happened" prompt,
  and any recent Flutter/async errors captured by `ProblemReportLog`
  (`lib/problem_report.dart`, hooks on ui/background/overlay engines, stored
  in SharedPreferences). Still no network crash SDK. Hard native crashes
  remain uncaptured — email copy explains that.
- **[P1] "Report a problem" was effectively non-functional — fixed and merged
  2026-08-11 (PR #15), one piece still open.** Root-caused after a tester (Dinesh)
  reported empty logs on every attempt. Five causes found, two fixed and confirmed
  on-device (`docs/TEST_PLAN.md` cases 78–81, `flutter analyze`/`flutter test` clean):
  - **Fixed:** `ProblemReportLog` used `SharedPreferences.getInstance()`,
    the exact per-isolate-singleton-caching bug `AppSettings` was written to
    avoid (CLAUDE.md §3). Across the ui/background isolates this meant (a)
    the About screen could read a stale cached copy that never saw errors
    the background isolate recorded later in the same session, and (b)
    because `record()` does read-modify-write, a stale read could clobber
    every entry another isolate had written since. Swapped to
    `SharedPreferencesAsync` (reads platform fresh every call), matching
    `AppSettings`'s own pattern.
  - **Fixed:** the mailto URIs (`Send feedback` + `Report a problem`) were
    built via `Uri(queryParameters: ...)`, which form-encodes spaces as
    literal `+` — several mail apps (Gmail included) don't decode that back
    on a `mailto:` link, so subject/body arrived full of stray `+`
    characters. Switched to hand-built percent-encoding
    (`Uri.encodeComponent`, RFC 6068).
  - **Still open — overlay isolate cannot record anything, at all.** The
    overlay engine has zero plugins registered (see `lib/main.dart`'s note
    on why — same reason `flutter_overlay_window`'s old `shareData()` bridge
    was replaced by `IsolateNameServer` ports), so `SharedPreferencesAsync`
    throws `MissingPluginException` there and `record()`'s catch swallows it
    silently. This is exactly where the bubble and capture screen live, i.e.
    the isolate most likely to actually throw. Fix needs a relay through the
    background isolate's ports (same pattern as `_intentWritePortName`) —
    deliberately NOT built blind in the no-device session above, since
    landing new isolate/port wiring untested is exactly the failure mode
    CLAUDE.md §3's four "real bugs found" gotchas all trace back to.
    **Re-confirmed on-device 2026-08-11** (`docs/TEST_PLAN.md` case 81): an
    overlay-isolate error still doesn't reach the log, no crash — behavior
    unchanged, still needs the port-relay fix above, not a new regression.
  - **Also noted, not yet acted on:** the buffer only catches *uncaught*
    Dart exceptions and can lose the write if the process dies before an
    `unawaited(record(...))` lands — most of the actual failure modes in
    CLAUDE.md §3 (hangs, locally-caught errors) never reach these hooks at
    all. A background-isolate breadcrumb trail (lifecycle events, not just
    exceptions) would likely surface more than exception logging ever will.
    Play Console → Android vitals already has fatal/ANR data for the closed
    test with zero code changes — check there first.

- **[DONE 2026-08-11, PR #15] `flutter_overlay_window` crashes on service restart
  (`NullPointerException` in `OverlayService.onStartCommand`) — found via Play
  Console Android vitals 2026-08-02.** Affected 3 closed testers (Nothing Phone, a
  Pixel, a Samsung) — Android killed the bubble's background service under memory
  pressure and restarted it per normal `START_STICKY` behavior, which delivers a
  `null` `Intent`; the plugin dereferenced it immediately with no null check, at
  `intent.getIntExtra(...)`. `0.5.0` (our pinned/latest version) did NOT fix this
  specific case despite its changelog claiming an `OverlayService` NPE fix (that was
  a different one) — no newer plugin version exists to upgrade to. Entirely native —
  `ProblemReportLog` can never see it (CLAUDE.md §3's "native crashes leave no
  Flutter log" caveat, confirmed for real here). Fixed via a fork
  (`diniiidinesh/flutter_overlay_window`, branch `fix/overlay-service-null-intent`)
  with a one-line null guard, wired in via a git dependency in `pubspec.yaml`.
  Confirmed on-device (`docs/TEST_PLAN.md` case 82): `adb shell am crash` twice with
  the bubble live, Android genuinely rescheduled the null-Intent restart both times,
  zero `NullPointerException`/`FATAL EXCEPTION` afterward. Upstream issue filed by
  Dinesh 2026-08-11. **Ongoing:** keep the fork until (if) the upstream maintainer
  merges a fix, then drop back to the official package. Full RCA:
  `docs/debug/rca-overlay-service-null-intent-crash-2026-08-02.md`.

- **[DONE 2026-08-11] Edge-to-edge (Android 15+, `targetSdk 36`).** Google Play
  Console flagged that apps targeting SDK 35+ display
  edge-to-edge by default and need to handle insets correctly. `targetSdk` here is 36
  (`android/app/build.gradle.kts`), well past that threshold — and at 36, Android
  removes the manifest opt-out flag entirely, so there's no "avoid this" path; the fix
  has to be real. Not about the bubble/overlay (drawn via `WindowManager` from a
  service, not the Activity — edge-to-edge is an Activity-window concept, doesn't
  apply there). Flutter's engine already runs edge-to-edge by default
  (`decorFitsSystemWindows = false`), so `enableEdgeToEdge()` (the native/Kotlin
  remedy Google's message is templated for) isn't the applicable fix — this is a Dart
  layout question. Audited all 9 `Scaffold`s in `lib/`: 3 already used `SafeArea`
  (`home_screen.dart`, `main.dart`, `onboarding_screen.dart`); 5 didn't
  (`about_screen.dart`, `history_screen.dart`, `settings_screen.dart`,
  `status_screen.dart`, `manage_presets_screen.dart`) — all bare
  `Scaffold(body: ListView(...))`, so on a gesture-nav device the bottom of scrollable
  content could sit under the system nav bar; `manage_presets_screen.dart` also has a
  `floatingActionButton`, the highest-risk case since it's fixed-position, not
  scrollable. Fixed by wrapping each of the 5 bodies in `SafeArea(top: false, ...)`
  (Dart-only, no native/Kotlin files touched). Confirmed on-device 2026-08-11 —
  enough bottom clearance on all 5 screens for the gesture nav bar
  (`docs/TEST_PLAN.md` cases 83–84).

- **[DONE 2026-08-11] Bubble glow rendered as a flat tinted square, not a soft
  halo.** Reported by Dinesh from actual device use: an orange
  hue filled the bubble's whole square footprint rather than staying within the
  circle. Root cause: `_BeaconGlassShell`'s `BoxShadow` (`lib/bubble_widget.dart`)
  needs ~12.5dp to blur and fade to nothing, but the native overlay window is sized
  to exactly match the bubble's own bounds (52dp collapsed) with zero margin — a
  circle's corner-to-window-corner gap is only ~10.8dp, less room than the blur
  needs, so it got hard-clipped at the window edge instead of fading, reading as a
  flat tint rather than a halo. Two fix options were weighed: give the window extra
  margin so the blur can fade properly (preserves the design doc's "soft glow" intent
  more faithfully, but touches window-size math shared across bubble
  show/drag-snap/orientation-reopen call sites — a fragile, bug-prone area per
  `docs/ARCHITECTURE.md` §5) vs. clip the shadow to the shape exactly (guarantees zero
  color beyond the circle, Dart-only, zero risk to shared geometry code, but loses the
  external glow entirely). **Dinesh chose the clip.** Implemented by wrapping
  `_BeaconGlassShell` in `ClipRRect` and removing the now-dead `BoxShadow` +
  `BeaconColors.amberGlow` token (a shadow clipped exactly to its own source shape
  paints nothing, so keeping it would've been dead code) — see
  `docs/erd/beacon-visual-identity-2026-07-24.md`'s update log for the full before/
  after. The bubble now has a crisp amber rim with no external glow; reintroducing one
  later needs extra window margin, not just a shadow tweak. Confirmed on-device
  2026-08-11, both collapsed and expanded (`docs/TEST_PLAN.md` cases 85–86).

- **[DONE 2026-08-11] Re-added "Call someone" preset with its icon.**
  Dinesh's request — "Calls" existed in the original pre-verb default set
  (`legacyDefaultPresetLabels`) but was dropped when the 2026-07-25 verb-preset
  redesign (`docs/erd/verb-presets-job-goers-2026-07-25.md`) replaced category
  nouns with action verbs. Re-added as **"Call someone"** (matching the verb-phrase
  convention of "Message someone"/"Pay someone", not the old "Calls" noun), placed
  right after "Message someone" since both are communication actions. The icon
  (`Icons.call`) was already sitting in `lib/bubble_icons.dart` from the legacy
  `'calls'` mapping — just needed a `'call someone'` case added alongside it (and to
  `_knownPresetLabelsLower`, so it gets the phone icon instead of a letter avatar).
  `defaultPresetLabels` is now 6 items instead of 5; `maxEnabledPresets = 8`, so no
  capacity conflict. Existing testers who never touched their presets get migrated
  automatically — added `verbPresetLabelsV3` (the outgoing 5-item set) to the
  seed-migration match list and bumped `defaultPresetsSeedVersion` 3→4, following the
  exact pattern already used for the legacy→v2 and v2→v3 migrations
  (`IntentStore._ensureDefaultPresetSeed`). Testers who *did* customize their presets
  are left alone, same as every prior seed bump — this only touches untouched
  installs. New migration test added (`test/intent_store_test.dart`, "seed v4
  migrates untouched verb-v3 defaults"). Confirmed on-device 2026-08-11: fresh
  install, Restore defaults, and the preset's icon/behavior all correct
  (`docs/TEST_PLAN.md` cases 66/71/71b). **Case 69 (the v3→v4 auto-migration for
  existing testers who never touched their presets) is still unverified** —
  requires an "upgrade an existing install" scenario, not exercised by the
  fresh-install/Restore-defaults checks above; lower priority since it only
  affects existing testers' next unlock, not new installs.

- **[decision] Raise `maxEnabledPresets` from 8 to 10 — deferred pending user
  feedback, not rejected.** Requested 2026-08-11 alongside the "Call someone"
  preset addition. Technically safe to raise (capture screen presets render in a
  `Wrap` inside a `SingleChildScrollView`, `lib/main.dart` — extra presets just
  wrap to more rows, no overflow/low-end-device risk). Held at 8 instead because
  the existing cap is a *documented behavioral* decision, not a technical one —
  `docs/DATA_MODEL.md` §7: "decision cost, not screen space" is the binding
  constraint, current cap 8 with 5–6 *recommended*. Rather than guess whether 10
  helps or hurts, added the actual question to
  `docs/USER_INTERVIEWS.md` (Presets / capture screen) to ask real testers.
  Revisit once that's been asked.

- **[decision] Full crash reporting / Crashlytics** — still deferred. See prior
  note: opt-in network reporting only when N outgrows 1:1 support; flips Data
  Safety in the same release.

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
