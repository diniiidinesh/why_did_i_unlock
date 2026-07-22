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
| `test/intent_store_test.dart` | `IntentStore` repository (cases 1–9): insert/read, empty DB, SQL-injection literal stored verbatim, idempotent `client_id`, input validation (5 sub-cases via `fromMessage`), no-intent row shape, `recentEvents` limit+ordering, `lastCompletedAt` across kinds, schema-migration reopen. |
| `test/prompt_policy_test.dart` | Triage policies (cases 10–12): `ProbabilityPromptPolicy` bounds + seeded determinism, `TimeCooldownPolicy` boundary (`>=`), `CompositePromptPolicy` AND-semantics. |
| `test/widget_test.dart` | `HomeScreen` renders title/toggle/history entry (13); `IntentCaptureScreen` renders presets/pill/field/OK (14). |
| `test/history_screen_test.dart` | `HistoryScreen` renders events newest-first, styles `no_intent` rows distinctly (15). |

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
