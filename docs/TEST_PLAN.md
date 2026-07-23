# TEST_PLAN — what's covered, what's verified on-device

> Living test tracker for **Why Did I Unlock**. Grows sprint over sprint so we keep a
> durable, git-tracked record of *which behaviours are touched and how they're checked* —
> not just what code exists. Automated tests are the source of truth for logic; this doc
> is the source of truth for the **manual on-device matrix** (unlock/overlay/reboot
> behaviour that emulators and `flutter test` cannot reproduce).
>
> Update rule (per `docs/DOC_UPKEEP.md`): mark a manual case's Status/Evidence in place
> when you run it; add new rows when a new behaviour area is touched. Don't duplicate the
> automated tests' assertions here — point to the file, one line each.

## Automated tests (run: `flutter analyze` + `flutter test`)

These live in git under `test/` and run on every check. One line each — read the file
for the exact assertions.

| File | Covers |
|---|---|
| `test/intent_store_test.dart` | `IntentStore` repository. **Sprint 3 (1–9):** insert/read, empty DB, SQL-injection literal stored verbatim, idempotent `client_id`, `fromMessage` validation (7 sub-cases incl. `presetId` typing + `toMessage` round-trip), no-intent row shape, `recentEvents` limit+ordering, `lastCompletedAt` across kinds, reopen. **Sprint 4 (20–25):** real v1→v2 migration from a hand-built v1 file, `unlock_log` round-trip incl. every `SkipReason`, declare→dismiss lifecycle (`open`/`done`/`abandoned`, idempotency, no-op on unknown id, **no resurrection of abandoned rows**), `unlock_id` stateless resolution (incl. later-skipped-unlock and no-prompted-unlock cases), preset CRUD + limits + soft-delete + restore-defaults. |
| `test/app_settings_test.dart` | `AppSettings` (30–35): defaults match the previously-hardcoded constants, round-trips, **clamping on both write and read**, retention enum mapping + sentinel, quiet-hours flag independent of window, `loadSnapshot` batching, cross-instance visibility. |
| `test/prompt_policy_test.dart` | Triage policies. **Sprint 3 (10–12):** `ProbabilityPromptPolicy` bounds + seeded determinism, `TimeCooldownPolicy` boundary (`>=`), `CompositePromptPolicy` AND-semantics. **Sprint 4 (40–42):** `QuietHoursPolicy` same-day window, **overnight wraparound**, inclusive-start/exclusive-end boundaries, degenerate zero-width window fails open. |
| `test/widget_test.dart` | `HomeScreen` renders title/toggle/history entry (13); `IntentCaptureScreen` renders presets/pill/field/OK (14), an empty preset list (16, T11's zero-presets state), tapping a preset passes its id back through `onSubmit` (17), custom text carries no `presetId` (18). |
| `test/history_screen_test.dart` | `HistoryScreen` renders events newest-first, styles `no_intent` rows distinctly (15). |

### What automated tests deliberately do **not** cover

Two hard limits, both structural rather than laziness — they define the manual matrix below:

1. **`_showCaptureScreen` and the whole unlock write path are unreachable from tests.**
   They're private (Dart's leading-underscore privacy is per-library, so a test file
   genuinely cannot call them) and depend on `flutter_overlay_window`'s platform channel
   plus `IsolateNameServer` ports that only behave correctly inside a real Android
   process with three live Flutter engines. Every triage *decision* is unit-tested via
   its policy class; the *wiring* that calls them is not, and can only be verified
   on-device by reading logs.
2. **A green `flutter test` does not prove the sqflite path works on-device.**
   `sqflite_common_ffi` (desktop) tolerates SQL that Android's backend rejects — this is
   not hypothetical, it is exactly how the `PRAGMA journal_mode=WAL` `execute()`-vs-
   `rawQuery()` bug reached a device undetected (`docs/ARCHITECTURE.md` §5). **Any change
   touching schema or queries needs at least one real read/write cycle on hardware.**

## Manual on-device matrix (physical device only — e.g. A063)

Status legend: ✅ verified · 🟡 partially verified · ❌ not yet run · ⛔ blocked

### Sprint 3 — storage, triage, history

| # | Case | Status | Evidence / notes |
|---|---|---|---|
| 16 | Declare intent → dismiss → row written (kind=intent, correct source) & shown in History | 🟡 | Write confirmed via logs (`💾 Stored event`); visual History re-check pending |
| 17 | "Just Like That" → no bubble, `no_intent` row written & shown in History | 🟡 | Write confirmed via logs; visual History re-check pending |
| 18 | Cooldown floor blocks re-prompt within 1 min | ✅ | Logs: `COOLDOWN active (elapsed … < 0:01:00)`, repeatedly |
| 19 | Probability varies across unlocks (not every time, ~half at p=0.5) | ✅ | Logs: real hit/miss mix over many draws |
| 20 | Cross-engine: swipe from Recents → declare/dismiss → row still written | 🟡 | Relay proven in pre-build spike; re-run with final `IntentEvent` write code pending |
| 21 | Concurrent read/write: History open during a write → no crash (WAL) | 🟡 | Drove the `ownConnection` fix (sqflite `singleInstance`); needs a clean re-run |
| 22 | Reboot → monitoring resumes → dismiss writes a row (direct-boot path) | ❌ | Not yet run |
| 23 | Single-active-intent: unlock while a bubble is live → no re-trigger, no spurious row | ❌ | Not yet run |
| 24 | `allowBackup=false` verified on-device (`adb shell dumpsys backup`) | 🟡 | Manifest attribute source-verified; dumpsys not run |

### Interruption / lifecycle edge cases (opened by the reboot bug, 2026-07-22)

Class of bug: **what happens to "is a prompt/bubble live" state when an event is interrupted
mid-flight** (reboot, process kill, dropped close-signal). Symptom that opened this: a capture
prompt was left open across a device reboot; afterwards *no* prompts appeared at all — the
active/triage state appears to have latched and did not self-heal.

| # | Case | Status | Expected behaviour |
|---|---|---|---|
| 25 | Reboot **with a capture prompt open** → boot → unlock | ✅ | **Fixed & verified on-device 2026-07-22.** Root cause: `IntentStore.open()` failed once at direct-boot with `errno 126 (ENOKEY)` — credential-encrypted storage still locked before first unlock — and was never retried, permanently nulling `_intentStore`, which broke cooldown (`lastCompletedAt` always null) AND all future writes for the process. Fix: idempotent `_ensureIntentStore()` retried at write-time + each triage check (+ concurrent-open guard). Device logs confirm: retry logs `💽 IntentStore opened` on next unlock, then `COOLDOWN active (elapsed … < 0:01:00)` blocks re-prompts again. See `docs/debug/sprint3-session-log-2026-07-22.txt` UPDATE 4 |
| 26 | Reboot **with a live bubble** (declared, not dismissed) → boot → unlock | ✅ | Verified via Terminal 5 (2026-07-22): post-reboot process (`errno 126` → retry → `💽 IntentStore opened`) resumes cleanly; prompts and cooldown work, no latched-active state |
| 27 | App process killed (not reboot) mid-prompt → unlock | ✅ | Verified 2026-07-22: fresh process does not inherit a stuck active flag; overlay-active guard resets on cold start |
| 28 | Capture prompt open, screen locks (no dismiss) → unlock | ✅ | Verified 2026-07-22: unlock while overlay still up logs `🟡 Overlay already active, skipping re-trigger` — guard not latched, existing prompt reused |
| 29 | Overlay-closed signal dropped/never arrives → next unlock | ✅ | Verified 2026-07-22 as part of the interruption pass; state self-heals (no permanent wedge). NOTE: no *explicit* dropped-signal fault injection yet — see caveat below |

**Design through-line for the fix:** `_overlayIsActive` (and anything gating on "a prompt/bubble
is live") needs (a) a defined **reset on background-engine cold start**, and (b) a **safety
timeout** so a missed overlay-closed signal self-heals. Case 29 is the "didn't heal after that"
symptom directly.

### Sprint 4 — schema v2, settings, unlock logging

Run with a second terminal open on `flutter logs -d A063`. Cases 30–33 are the
**upgrade-safety gate** — run them before anything else, because every later case
assumes the migration landed correctly.

Reading the DB directly (several cases below need it): the on-device `sqlite3` CLI is
**not reliably present** — confirmed absent on the test device (`run-as: exec failed for
sqlite3: No such file or directory`). Use the pull-and-query-locally approach instead,
which needs nothing installed beyond what's already a project dependency
(`sqflite_common_ffi`):
```powershell
$adb = "<path to adb.exe>"
$pkg = "com.whydidiunlock.why_did_i_unlock"
cmd /c "`"$adb`" exec-out run-as $pkg cat databases/intents.db > `"$env:TEMP\pulled_intents.db`""
cmd /c "`"$adb`" exec-out run-as $pkg cat databases/intents.db-wal > `"$env:TEMP\pulled_intents.db-wal`""
cmd /c "`"$adb`" exec-out run-as $pkg cat databases/intents.db-shm > `"$env:TEMP\pulled_intents.db-shm`""
```
**Pull all three files, not just `intents.db`** — this database runs in WAL mode, so
recent writes can sit in the `-wal` sidecar until SQLite checkpoints them into the main
file. Pulling `intents.db` alone can show a false "empty" result (confirmed on-device
2026-07-23: `intents.db` alone was a stale, correctly-seeded-but-otherwise-empty
45KB file across an entire test session, while its `-wal` sidecar held 280KB of the
actual unlock/intent history). Query the pulled file with a throwaway Dart script using
`sqflite_common_ffi` (same package this project's own tests already depend on) —
`databaseFactoryFfi.openDatabase(path)` picks up the sibling `-wal`/`-shm` files
automatically as long as they share the base filename and sit in the same directory.
Requires **`run-as`, which needs a debuggable build** (`flutter run` without
`--release` — a release build's `android:debuggable=false` blocks `run-as` entirely,
which is expected, not a bug: see `CLAUDE.md` §5's security review).

| # | Case | Status | Expected behaviour / what to look for |
|---|---|---|---|
| **30** | **Upgrade install over v0.5.0+7** (do NOT uninstall first) | ❌ | App opens, no crash. This is the only way to exercise the real `onUpgrade` — the automated migration test builds its v1 file in `sqflite_common_ffi`, which is exactly the backend that has previously masked an Android-only SQL failure. |
| 31 | After #30, open History | ❌ | Every pre-upgrade event still listed, unchanged. Confirms existing rows survived with `status` defaulted to `done`. |
| 32 | After #30, verify the new tables exist | ❌ | `sqlite3 … '.tables'` shows `intent_log`, `unlock_log`, `intent_preset`; `SELECT COUNT(*) FROM intent_preset` = 5. |
| 33 | Fresh install (uninstall first) | ✅ | Verified on-device 2026-07-23: fresh `intent_preset` table seeded with all 5 defaults, enabled, `deleted_at` null. Confirms `onCreate` (schema-creation-plus-seed-in-one-shot path, distinct from `onUpgrade`) works correctly. |
| **34** | **Normal unlock → prompt shown** | ✅ | Verified on-device 2026-07-23: `unlock_log` shows multiple rows with `prompt_shown=1, skip_reason=null`, each with a matching `intent_log` row from that session. |
| 35 | Unlock blocked by cooldown | ✅ | Verified on-device 2026-07-23: 5 separate `unlock_log` rows with `skip_reason='cooldown'` across the session. |
| 36 | Unlock blocked by probability | ✅ | Verified on-device 2026-07-23: 3 separate `unlock_log` rows with `skip_reason='probability'`. |
| 37 | Prompts toggled OFF in-app → unlock | ❌ | Not yet run. |
| 38 | Unlock while a bubble/capture screen is already live | ✅ | Verified on-device 2026-07-23: one `unlock_log` row with `skip_reason='overlay_active'`, landing right after a declared-but-undismissed intent, exactly the scenario expected. |
| 39 | Revoke "Display over other apps", then unlock | ✅ | Verified on-device 2026-07-23 — arose naturally before the fresh install's permission was granted: `unlock_log` row 1 shows `skip_reason='no_permission'`. |
| **40** | **Quiet hours suppresses prompts** | ❌ | No Settings UI until T13, so set it by hand: `adb shell "run-as … sqlite3"` won't work (it's `shared_preferences`, not sqflite) — easiest is to wait for T13, or temporarily flip `AppSettings.defaultQuietHoursEnabled` to `true` in a debug build. Expect `🌙 Quiet hours active`, `skip_reason='quiet_hours'`. |
| 41 | **Overnight quiet-hours window across midnight** | ❌ | With a 22:00–07:00 window: suppressed at 23:00 **and** at 03:00; NOT suppressed at 12:00. The wraparound logic is unit-tested, but confirm the device's local timezone resolves as expected (the policy uses local `DateTime`, not UTC). |
| 42 | Declare → dismiss still works end-to-end | ❌ | Regression check: `_submitIntent`/`_dismissBubble` are untouched by T9, so behaviour must be identical to v0.5.0+7. Row written, bubble appears and closes. |
| 43 | Logging failure cannot suppress a prompt | ❌ | Hard to force deliberately; verify the weaker version — across a long session, no unlock is ever *missing* a prompt that triage said should show. Any `⚠️ Failed to log unlock (non-fatal)` in logs must be followed by the prompt still appearing. |
| 44 | Battery/latency sanity after adding a write per unlock | ❌ | Unlock→prompt still feels immediate (`CLAUDE.md` §8's ~500ms target); no new jank. The `unlock_log` insert is deliberately after `showOverlay()`, so a regression here would indicate the ordering broke. |

**Not yet reachable (needs later tasks):** preset editing (T16), settings screen round-trip
including the cross-isolate propagation check (T13), CSV export (T17). Cases will be added
as those land rather than listed here as permanently ❌.

### Sprint 4 — declaration-time writes and the abandoned-intent sweep (T10)

The relay protocol changed shape: declaring an intent and dismissing it are now two
separate messages (`declare` then `dismiss`) instead of one full event sent at dismissal.
Read `docs/DATA_MODEL.md` §4 before running these if the "why" isn't obvious from the
case descriptions alone.

Pull `intents.db` + `-wal` + `-shm` per the technique at the top of the Sprint 4 section
above and query locally — the on-device `sqlite3` CLI isn't reliably available, and
pulling `intents.db` alone can show a false-empty result if writes are still sitting in
the WAL sidecar (hit exactly this on 2026-07-23; see that section's note).

| # | Case | Status | Expected behaviour |
|---|---|---|---|
| 47 | Declare an intent (tap a preset) | ✅ | Verified on-device 2026-07-23: row appears immediately with `status='open'`, `completed_at` equal to `declared_at` (the placeholder), well before dismissal. |
| 48 | Dismiss that bubble | ✅ | Verified on-device 2026-07-23: same `client_id`, `status` flips to `done`, `completed_at` updated to the real dismiss time, `declared_at` unchanged. Confirmed across 3 separate declare→dismiss cycles in one session. |
| **49** | **Declare an intent, then force-stop or reboot before dismissing** | 🟡 | **Half confirmed on-device 2026-07-23 — the critical half.** Declared an intent, force-stopped before dismissing: the row survived as `status='open'` rather than vanishing (the core guarantee). **Not yet confirmed:** the `open`→`abandoned` sweep itself. Force-stop kills the process and disables `START_STICKY` auto-restart until manual relaunch (`ARCHITECTURE.md` §6) — the sweep only runs on the next `backgroundMain` start, which hasn't happened yet since the force-stop. **Next step: reopen the app, then re-pull and confirm this row now reads `status='abandoned'`.** |
| 50 | "Just Like That" still works unchanged | ❌ | Not yet run — no `kind='no_intent'` row appears anywhere in the session pulled 2026-07-23. |
| 51 | Declare, dismiss, declare again (two intents in sequence) | ✅ | Verified on-device 2026-07-23: 3 distinct completed declare→dismiss cycles in one session, each with its own `client_id`, none reused or leaked. |
| 52 | A `dismiss` message with no prior `declare` reaching the store (simulate: kill the app between tapping a preset and the relay landing) | ❌ | Hard to force deliberately on-device; if observed naturally, expect no crash and no row — `markIntentDone`'s `WHERE status='open'` clause matches nothing, silently. Log would show `✅ Intent marked done` (the relay call succeeded) but the DB row never existed to begin with. Note if this ever happens; not expected to reproduce easily. |
| **53** | **"Show me the prompt now" (Status screen, T6) — blocked until T6 lands** | ⛔ | Tap the button while prompts are disabled/in cooldown/in quiet hours → the capture screen still appears (bypasses triage by design). No `unlock_log` row is written for it (check via the case-30 `sqlite3` query — count should not increase). Tap it twice quickly → second tap is a no-op, logged `🧪 Manual prompt trigger: overlay already active, skipping` (same guard a real double-unlock hits). Revoke overlay permission first → tapping logs `🧪 Manual prompt trigger: permission not granted, cannot show` and nothing appears — confirms the button surfaces a real permission problem rather than silently succeeding. |

**Why case 49 matters most:** every other Sprint 4 change so far has been additive
(more logging, a settings layer). This one changes what happens to *data that already
existed conceptually* — before T10, an intent was only real once dismissed; a crash
mid-flight meant it never happened at all as far as the database was concerned. Confirming
the abandoned-sweep path on a real device, not just in the automated test that simulates it
via a direct `sweepOpenToAbandoned()` call, is the one thing here that can't be inferred
from code review.

### Sprint 4 — config relay: DB-backed presets on the capture screen (T11)

The capture screen's pills are no longer the hardcoded `Payments/Calls/Messages/Food
Order/Commute` list — they're fetched live from `intent_preset` via a new relay. This
is the first port in the app registered by the OVERLAY isolate rather than
`backgroundMain`; the on-device check below is specifically about confirming that
works at all, not just that the data is correct.

| # | Case | Status | Expected behaviour |
|---|---|---|---|
| **54** | **First unlock after a fresh install/reboot (cold overlay engine)** | ✅ | Verified on-device 2026-07-23: preset declares from the very first session all show correct `preset_id` values, which is only possible if the config relay delivered presets successfully on the overlay engine's first cold start. Log line itself (`📤 Sent N preset(s) to overlay`) not independently screenshotted this pass — the DB evidence is conclusive regardless. |
| 55 | Rename a preset (once T16 lands — until then, edit `intent_preset.label` directly via `sqlite3`), then lock and unlock | ❌ | The capture screen shows the NEW label on this next unlock — confirms the re-request-on-return-to-capture-mode path, not just the cold-start one. |
| 56 | Disable a preset (or edit `intent_preset.enabled=0` via `sqlite3`), then unlock | ❌ | That preset's pill no longer appears; the rest render unchanged. |
| 57 | Declare an intent from a preset pill, check the DB | ✅ | Verified on-device 2026-07-23: 3 preset-sourced declares, each `preset_id` correctly matching the tapped preset (`Commute`→5, `Food Order`→4 twice). Closes the T10-era gap where `presetId` was always null. |
| 58 | Declare from the custom text field (not a preset pill) | ✅ | Verified on-device 2026-07-23: a custom-text declare (typed "Messages" rather than tapping the preset) correctly recorded `source='custom'`, `preset_id=null` — confirms custom text never gets a spurious preset link even when it happens to match a preset's label. |

**What would look broken but isn't:** a very brief (sub-second, likely imperceptible)
render of the capture screen with **no pills at all** — just the text field and "Just
Like That" — on the very first show after a cold overlay-engine start, before the
first `requestPresets` reply lands. This is the documented, deliberately-valid
zero-presets state (docs/DATA_MODEL.md §7), not a bug; if it's visually noticeable
rather than instantaneous, that's worth flagging as a real latency finding, but the
absence of pills itself is expected for that one frame.

### Native — `UpdateReceiver` (added 2026-07-23, outside the T-numbered task list)

Pure Kotlin/manifest — nothing here is reachable by `flutter test`. Found via an
on-device build push during Sprint 4; `flutter run` masks this entirely because it
always auto-launches the app after installing, so this needs a path that does NOT
auto-launch.

| # | Case | Status | Expected behaviour |
|---|---|---|---|
| 45 | Build a release APK, install via `adb install -r` (NOT `flutter run`), do **not** open the app, then unlock the phone | ✅ | Verified on-device 2026-07-23 (Nothing Phone, "Spacewar", Android 15): `WDIUUpdate: 🔁 Restarting UnlockListenerService after app update` fires within ~1s of install, immediately followed by `🧠 backgroundMain ready` and `💽 IntentStore opened` — with no manual launch. First attempt (before the app had been opened at all post-boot) showed zero trace anywhere in logcat, no crash; `dumpsys` confirmed the process was fully dead and the receiver correctly registered. Second attempt, after opening the app once to re-establish a normal running baseline, fired cleanly and repeatably (confirmed across 2 separate reinstalls). The first attempt's silence is not yet fully explained — see note below. |
| 46 | Same as #45, but check the ongoing notification | 🟡 | Not independently re-checked this pass — inferred from `IntentStore opened` appearing, since that only happens after `UnlockListenerService.onCreate` posts the notification. Worth a direct visual glance next time. |

**Open question from case 45:** the first reinstall attempt (on a device where the app process was already dead, having never been reopened since an earlier `flutter run`) produced no trace of the receiver firing at all — not even a crash. The second attempt, after manually opening the app once first, worked cleanly and has now repeated successfully twice. Whether that first-attempt silence was a one-off (stale `PackageManager` install session, some transient device state) or a real, reproducible precondition (e.g. the app needs to have been launched at least once in the current boot cycle for `MY_PACKAGE_REPLACED` delivery to be reliable on this device) is not yet known. If it recurs, treat it as a real finding — it would mean `UpdateReceiver` alone isn't sufficient and the OEM-autostart onboarding item (`[P1]`, `docs/BACKLOG.md`) needs to also cover "open the app after installing," not just after boot.

Command for #45/#46:
```bash
flutter build apk --release
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c && adb logcat -s WDIUUpdate WDIUBoot flutter
```
Then lock/unlock the phone without ever tapping the app icon.
