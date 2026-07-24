# RCA — Post-reboot overlay stall, force-stop recovery, and empty presets

> **Date:** 2026-07-24  
> **Device:** Nothing Phone (1) / A063, Android 15 (stock — **not** Vivo/Xiaomi OEM-autostart class)  
> **App:** Why Did I Unlock `0.6.0+8` era / Stage B branch work  
> **Owners of the investigation:** Dinesh (on-device), Claude Code (diagnosis-only for the stall), Cursor (implementation)  
> **Status:** Fixes landed in Dart; on-device verify still in progress for the stall hypothesis. Empty-presets poisoning was **log-proven** and fixed the same day.  
> **Companion gotchas:** `docs/ARCHITECTURE.md` §5 / §8; earlier related work in `docs/debug/sprint3-session-log-2026-07-22.txt`

This document is the durable “how we found it / how to recognize it again” record for a cluster of post-reboot failures that all look like “the app stopped working until I force-stopped it,” but are actually **several distinct failure modes** sharing the same recovery gesture (process death). Do **not** collapse them into “OEM killed the service” on a Nothing Phone without reading the log fingerprints below.

---

## 1. Symptom cluster (what the user saw)

Reported together, after reboot (often with a bubble still open from the previous session):

| Symptom | User-facing | Cleared by force-stop + reopen? |
|---|---|---|
| A. No unlock prompts after reboot | Unlock phone → nothing | Yes |
| B. App stuck on loader / blank black screen | Opening the app UI hangs | Yes |
| C. Prompt appears but **preset pills are missing** | Capture screen empty of presets | Reopen / later unlock sometimes; not always force-stop |
| D. Expectation that “the app should open” after reboot | UI never auto-launches | N/A — **not a bug** (by design) |

**Design clarification (D):** After reboot, only `UnlockListenerService` (and thus `backgroundMain`) is supposed to start. The main UI activity is **not** meant to auto-open. Testers often confuse “monitoring is dead” with “UI didn’t open.” Separate those before debugging.

---

## 2. What this is *not* (ruled out with evidence)

Before attributing similar future reports to this RCA, rule these out with the same checks:

### 2.1 OEM autostart / battery kill (BACKLOG `[P0]` OEM)

- **Relevant for:** Vivo / Xiaomi / Oppo / similar — friends already hit this on Vivo.  
- **Not the default explanation for:** Nothing Phone (1) stock Android 15 in this investigation.  
- **Fingerprint if it *is* OEM:** no `🧠 backgroundMain ready` after reboot, no `WDIUBoot` lines, service not running until manual app open.  
- **Fingerprint here:** `WDIUBoot` fired, `backgroundMain` ready, unlocks reached Flutter — so monitoring *was* up.

### 2.2 Missing `@pragma("vm:entry-point")` / Flutter upgrade deleted `backgroundMain`

- Suspected after a Flutter upgrade to 3.44.x + reinstall.  
- **Ruled out:** logs showed `🧠 backgroundMain ready` and `💽 IntentStore opened` when the service ran. Entry point is present and executing.

### 2.3 BootReceiver never registered / `RECEIVE_BOOT_COMPLETED` missing

- **Ruled out** for the healthy sessions:  
  `WDIUBoot: onReceive … LOCKED_BOOT_COMPLETED` and `BOOT_COMPLETED` both appeared.  
- **Pitfall:** `adb shell am force-stop` puts the app in Android **stopped state**, which **withholds** boot broadcasts until the user manually launches the app once. That can fake “BootReceiver broken” during diagnosis. Prefer reboot testing without force-stop, or launch once after force-stop before the next reboot test.

### 2.4 UnlockReceiver not receiving anything

- **Ruled out** for several sessions: `SCREEN_OFF` / `USER_PRESENT` both logged.  
- When prompts were missing *with* unlock lines present, the bug was **past** the native receiver (triage / overlay / self-tracked state).

### 2.5 `flutter logs` noise

- `flutter logs` mixes **other apps’** Flutter engines (Shorebird updaters, Nothing-ecosystem `NtLifecycle`, Firebase init, etc.).  
- **Always prefer:**  
  `adb logcat -s WDIUBoot:D UnlockReceiver:D flutter:I`  
  and then filter by **our PID** (the one printing `🧠 backgroundMain` / `🔓 UNLOCK EVENT`).

---

## 3. Architecture context (why these bugs are possible)

Three Flutter engines, one process (see `docs/ARCHITECTURE.md` §1):

| Engine | Entrypoint | Role in this RCA |
|---|---|---|
| Background | `backgroundMain()` | Unlock triage, `showOverlay()`, DB writes, preset replies |
| Overlay | `overlayMain()` → `OverlayRoot` | Capture UI + bubble; **cached** for process lifetime; holds `_presets` |
| Main UI | `main()` → `AppLauncher` / `HomeScreen` | Settings/Home; can touch `flutter_overlay_window` permission APIs |

Critical shared facts:

1. **`_overlayIsActive`** is a plain `bool` in the background isolate, set `true` *before* `await showOverlay()`, cleared only when the overlay signals close (or, after the fix, on `showOverlay` timeout).  
2. **`flutter_overlay_window`** has a known class of hangs / messenger hijacks (`isActive()`, historical `shareData()` — Sprint 3 session log). Self-tracking + `_withTimeout` is the established defense.  
3. **Direct boot:** `backgroundMain` can run at `LOCKED_BOOT_COMPLETED` before credential-encrypted (CE) storage unlocks → `IntentStore.open()` fails with `errno 126` / `ENOKEY`. `_ensureIntentStore()` retries later — that path is correct and expected.  
4. **Overlay presets** are not read from DB in the overlay isolate (no plugins). They arrive only via IsolateNameServer config reply. An empty reply **caches** as `_presets = []` for that engine’s life until a good reply arrives.

```
BOOT / LOCKED_BOOT
  → UnlockListenerService → backgroundMain
  → (often) IntentStore.open fails ENOKEY — OK, retry later

USER_PRESENT (first unlock after CE available)
  → triage → _presentCaptureOverlay
       → _overlayIsActive = true
       → await showOverlay()          ← can hang (Bug A)
       → push presets to overlay      ← can race port-not-ready
  → overlay initState
       → register config port
       → requestPresets               ← can get timeout → [] (Bug C)
```

---

## 4. Bug A — Hung `showOverlay()` leaves `_overlayIsActive` stuck forever

### 4.1 Hypothesis (Claude Code diagnosis, 2026-07-24)

`FlutterOverlayWindow.showOverlay()` was the **one** unlock-path plugin call **not** wrapped in `_withTimeout`.

Sequence:

1. `_overlayIsActive = true` (deliberate: closes a re-entrancy race before the await).  
2. `await showOverlay(...)` never returns (same plugin / shared native messenger defect class as `isActive()` / historical `shareData()`).  
3. Overlay-closed signal never fires (overlay never fully presented / never closed).  
4. Every later unlock hits `if (_overlayIsActive) → skip as overlay_active` with **no error** — “nothing happens for many unlocks.”  
5. Force-stop kills the process → next `backgroundMain` starts with `_overlayIsActive == false` → “fixed.”

Matches: silent skip forever + force-stop recovery + main UI having touched the overlay plugin in-session (messenger attach-order precondition from Sprint 3).

### 4.2 Confidence

- **Mechanically sound** and consistent with ARCHITECTURE §5’s plugin defect class.  
- **Not yet proven** by a captured `⏱️ showOverlay() timed out` line on device in the first post-fix reboot (that reboot was healthy — see §7).  
- If the symptom returns **without** any `⏱️` line, reopen investigation — do not assume this fix “didn’t work”; the hang may be the `isActive()`-style case where Dart `.timeout()` never fires because the isolate never regains control. That would need a different strategy (e.g. parallel `Timer` that clears `_overlayIsActive` even if the await is stuck — carefully, so it doesn’t clear during a slow-but-successful show).

### 4.3 Fix applied

**File:** `lib/main.dart` → `_presentCaptureOverlay`

- Wrap `showOverlay()` in `_withTimeout('showOverlay()', …)`.  
- On timeout: set `_overlayIsActive = false`, log  
  `⏱️ showOverlay() timed out — resetting _overlayIsActive`, return `false`.  
- Caller `_showCaptureScreen` logs unlock as `SkipReason.pluginTimeout` (`promptShown: false`) instead of counting it as shown.  
- Manual Status trigger shares the same function (no separate change).

**Defensive (secondary, thinner evidence):** timeouts around `AppSettings.onboardingCompleted()` in `AppLauncher` and Home’s permission/settings load — hung prefs/plugin calls can leave blank/`CircularProgressIndicator` forever (symptom B).

### 4.4 Log fingerprints

| Line | Meaning |
|---|---|
| `🟡 Overlay already active, skipping re-trigger` / triage skip `overlay_active` repeatedly with **no** matching close | Suspect stuck flag |
| `⏱️ showOverlay() timed out — resetting _overlayIsActive` | Fix fired; next unlock should be allowed to try again |
| `🟣 showOverlay called` after a prior `⏱️` | Recovery without force-stop — **verify success** |
| Force-stop then immediate healthy prompts, no `⏱️` ever | Either Bug A never hung this session, or hang was non-timeoutable (see confidence note) |

---

## 5. Bug B — Main UI stuck on loader / blank screen

### 5.1 Candidates

1. `AppLauncher`: `_onboardingCompleted == null` → blank black `Scaffold` until prefs return.  
2. `HomeScreen`: `CircularProgressIndicator` until store + permission + `loadSnapshot` complete.  
3. User language “loader” may also mean the capture overlay waiting on presets (Bug C) — ask which surface.

### 5.2 Relation to Bug A

Not necessarily the same root cause. Main UI is a **different engine**. A hung background `showOverlay` does not by itself block `AppLauncher`. Shared theme: **untimeoutable plugin/prefs Futures** + process-level wedging that force-stop clears.

### 5.3 Fix applied

- `AppLauncher._load`: `_withTimeout` on `onboardingCompleted()`; on null degrade to `true` (show Home rather than permanent blank / re-onboarding).  
- `HomeScreen._load`: timeout permission + `loadSnapshot`; on null set `_loadFailed` instead of spinning forever.

---

## 6. Bug C — First post-reboot unlock prompts, but presets are empty (**log-proven**)

### 6.1 Captured timeline (2026-07-24 ~16:05, pid 4117)

Abbreviated from on-device `adb logcat`:

```
16:05:19  🧠 backgroundMain ready
16:05:19  ⚠️ IntentStore.open() failed … errno = 126   ← direct boot / CE locked (expected)
16:05:26  🔒 LOCK EVENT
16:05:52  🔓 UNLOCK EVENT
16:05:52  📋 Has overlay permission: true
16:05:54  💽 IntentStore opened                       ← CE available; first successful open
16:05:54  🎲 Triage: prompting
16:05:54  🟣 showOverlay called
16:05:55  ⚠️ Could not find overlay-config reply port — Presets dropped
              ↑ background push raced ahead of overlay initState
16:05:55  🔧 Overlay: config reply port registered
16:05:55  📮 Overlay: sending requestPresets (attempt 1/5)
16:05:59  ⏱️ IntentStore.insertUnlock() timed out after 5s
16:06:00  ⏱️ IntentStore.activePresets() timed out after 5s
16:06:00  📤 Sent 0 preset(s) to overlay (manual=false)   ← POISON
16:06:00  📥 Overlay: _presets now has 0 entries            ← CACHED EMPTY
```

### 6.2 Root cause (two cooperating bugs)

1. **Cold CE / DB contention after first unlock**  
   Store opens mid-unlock; `insertUnlock` and `activePresets` both hit `_withTimeout` and return null.

2. **Null treated as empty list**  
   `_replyActivePresetsToOverlay` did:
   ```dart
   final payload = (presets ?? const []).map(...).toList();
   port.send({'presets': payload, ...});
   ```
   A **failed** fetch was indistinguishable from “user disabled every preset.” The overlay then cached `_presets = []`.

3. **Overlay stopped retrying after a successful *send***  
   `_requestPresets` returned as soon as the background port accepted the message, even if background later aborted or replied with poison. One bad reply → empty UI for the rest of that cached overlay engine’s life (or until a later good push).

4. **Harmless race (not the poison itself)**  
   Background’s immediate post-`showOverlay` preset push often runs before the overlay registers `_overlayConfigPortName` → “Presets dropped.” Overlay’s own `requestPresets` is the reliable path — but only if the reply is correct.

### 6.3 Fix applied

**File:** `lib/main.dart`

1. **`_replyActivePresetsToOverlay`**  
   - Retry `activePresets()` up to 3× (500ms apart) after timeout.  
   - If still `null`, **do not send** — log  
     `⚠️ activePresets unavailable after N attempts — not overwriting overlay presets with []`.  
   - Only send when the query returns a real `List` (empty list still allowed for “all presets disabled”).

2. **`_OverlayRootState._requestPresets`**  
   - Track `_presetsConfigReceived` + Completer completed by the config-port listener.  
   - Retry until a **reply** arrives (or attempts exhausted), waiting up to ~6s per attempt — not “return on first successful send.”  
   - Avoids stacking five concurrent `activePresets` queries while the DB is warming.

### 6.4 Log fingerprints (after fix)

| Line | Good / bad |
|---|---|
| `📤 Sent 6 preset(s)` + `_presets now has 6 entries` | Healthy |
| `⚠️ activePresets unavailable … not overwriting … with []` | Failure contained; pills may populate on a later retry/reply |
| `📤 Sent 0 preset(s)` + `_presets now has 0 entries` **after** a `⏱️ activePresets` | **Regression** — null-as-[] is back |
| `Could not find overlay-config reply port` alone | OK if a later request/reply succeeds |

---

## 7. Verification results so far (same day)

### 7.1 Healthy reboot (prompt + presets OK)

One reboot showed full happy path without opening the main UI:

- BootReceiver fired; `backgroundMain` ready; unlock → triage → `🟣 showOverlay called` → `Sent 6 preset(s)`.  
- **No** `⏱️ showOverlay` line — Bug A’s timeout path was **not** exercised.  
- Confirms: monitoring can work post-reboot on this device without manual app open (symptom D expectation is wrong).

### 7.2 Healthy prompt, poisoned presets

Section 6 timeline — Bug C proven. Bug A not involved (`showOverlay` completed in ms).

### 7.3 Still needed

- Rebuild with Bug A + Bug C fixes.  
- Reboot with bubble open beforehand.  
- Confirm: first unlock has presets (or temporary `activePresets unavailable` then recovery **without** `_presets now has 0` from a timeout).  
- If “no prompts until force-stop” returns, capture whether `⏱️ showOverlay` appears.

---

## 8. How to investigate the next similar report (playbook)

### 8.1 Capture

```bat
adb logcat -s WDIUBoot:D UnlockReceiver:D flutter:I
```

Reproduce: bubble open → reboot → unlock (do **not** force-stop first). Note our PID from `🧠 backgroundMain`.

### 8.2 Classify in order

```
1. Did WDIUBoot fire?
   NO  → stopped state? OEM kill? package disabled?
   YES → continue

2. Did backgroundMain ready appear for our PID?
   NO  → service/entrypoint problem
   YES → continue

3. Did USER_PRESENT / UNLOCK EVENT appear?
   NO  → UnlockReceiver / registerReceiver / process dead mid-session
   YES → continue

4. After unlock, which branch?
   a) ⏱️ showOverlay timed out → Bug A path (fix should recover next unlock)
   b) overlay_active skips forever, no ⏱️ → stuck flag OR non-timeoutable hang
   c) 🟣 showOverlay + Sent 0 / _presets 0 after ⏱️ activePresets → Bug C regression
   d) 🟣 showOverlay + Sent N>0 → healthy; if UI empty, different bug (render)
   e) AppLauncher/Home spinner forever → Bug B / prefs hang

5. Did force-stop “fix” it?
   YES → process-scoped wedge (Bugs A/B/C class), not permanent install corruption
```

### 8.3 Do not

- Trust `flutter logs` alone.  
- Force-stop mid-diagnosis then claim BootReceiver is broken.  
- Blame OEM autostart on Nothing/Pixel without missing-boot fingerprints.  
- “Fix” empty presets by hardcoding the old preset list in the overlay isolate.

---

## 9. Code map (where to look)

| Concern | Location |
|---|---|
| `showOverlay` + `_overlayIsActive` + timeout reset | `lib/main.dart` → `_presentCaptureOverlay` |
| Unlock triage / overlay_active skip | `lib/main.dart` → `_showCaptureScreen` |
| `_withTimeout` helper | `lib/main.dart` |
| Preset reply + null guard + retries | `lib/main.dart` → `_replyActivePresetsToOverlay` |
| Overlay request / Completer wait | `lib/main.dart` → `_OverlayRootState._requestPresets` |
| Direct-boot store retry | `lib/main.dart` → `_ensureIntentStore` / `IntentStore.open` |
| AppLauncher prefs timeout | `lib/main.dart` → `_AppLauncherState._load` |
| Home load timeouts | `lib/home_screen.dart` → `_load` / `_awaitWithTimeout` |
| Skip reason for hung show | `lib/intent_store.dart` → `SkipReason.pluginTimeout` |
| Boot / service native | `BootReceiver.kt`, `UnlockListenerService.kt` — **do not touch unless Dart exhausted** |
| Plugin gotcha canon | `docs/ARCHITECTURE.md` §5, §8.1, §8.3 |
| Tactical tracking | `docs/BACKLOG.md` Reliability section |

---

## 10. Related prior art (same codebase)

| Incident | Doc | Lesson reused here |
|---|---|---|
| `shareData()` hang / messenger hijack | `docs/debug/sprint3-session-log-2026-07-22.txt` | Never trust untimeoutable overlay plugin calls; IsolateNameServer for cross-engine |
| `isActive()` hang | ARCHITECTURE §5 | Prefer self-tracked state over plugin query |
| Overlay `requestPresets` one-shot failure | BACKLOG / Sprint 4 note | Bounded retry on overlay side |
| ENOKEY on direct boot | ARCHITECTURE §5 / `_ensureIntentStore` | Retry store open; don’t treat first failure as permanent |
| Stale overlay `_presets` after Manage Options | BACKLOG P0 presets | Push presets on every `_presentCaptureOverlay` |

---

## 11. Follow-ups (not done in this RCA)

- Mark BACKLOG stall item `[DONE]` only after on-device verify of Bug A path (or close as “hypothesis unused but defensive keep”).  
- Consider a **parallel Timer** clear of `_overlayIsActive` if we ever prove `showOverlay` can starve `.timeout()` the way `isActive()` did.  
- Optional: defer `insertUnlock` off the critical path more aggressively so it cannot contend with `activePresets` on first CE unlock (today both can race under `_withTimeout`).  
- Keep OEM autostart onboarding as a **separate** P0 — different fingerprint, different product surface.

---

## 12. One-paragraph summary for a new session

Post-reboot “dead until force-stop” on a Nothing Phone was investigated as three modes: (A) hung `showOverlay` leaving `_overlayIsActive` true forever — fixed by `_withTimeout` + reset flag; (B) main UI prefs/permission hangs — defensive timeouts on AppLauncher/Home; (C) first unlock after CE unlock timing out `activePresets` and **sending `[]` to the overlay**, poisoning `_presets` — fixed by never sending on null, retrying the query, and waiting for a real config reply. BootReceiver and `backgroundMain` were healthy; OEM kill and missing entrypoints were ruled out. Full fingerprints and playbook above; gotchas mirrored in `docs/ARCHITECTURE.md` §5.
