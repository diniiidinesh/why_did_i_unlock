# ERD — Outstanding-intent prompt ("continue or something else?")

> Plan doc. Scoped 2026-08-15, **not yet built**. Owner: Dinesh.
> Prerequisite: the `closeOverlay()` hang fix (branch `fix/overlay-close-hang-stuck-flag`)
> must be verified on-device and in production first — see §7 Risks for why that
> ordering is not optional.

## Update log

- **2026-08-15** — Created. Scopes T12's deferred half: populating
  `outstandingIntents` and acting on it. Timer is explicitly out of scope and
  planned as the next piece of work after this.

---

## 1. Problem

When the phone is unlocked while an intent is still outstanding, the app shows
**nothing at all** — no prompt, no bubble refresh, no choice. The unlock is
logged as `skip_reason='overlay_active'` and silently dropped.

This is the intentional single-active-intent behaviour (`CLAUDE.md` §2), but it
has two real costs:

1. **It's a large share of unlocks.** In Dinesh's own export
   (`why_did_i_unlock_export_2026-08-15`), **48 of 109 unlocks** were
   `overlay_active` skips. Even excluding the stuck-flag bug period, a
   substantial fraction of unlocks are moments where the app deliberately says
   nothing — for a product whose thesis is surfacing intention.
2. **It made a P0 invisible.** The 2026-08-15 stuck-flag bug looked *identical*
   to correct behaviour from the outside: both are "unlock, nothing happens."
   A visible "still doing X?" screen would have surfaced that bug on day one
   instead of after ~16 hours and four rounds of diagnosis. Observability is a
   real, secondary argument for this feature.

Long-running intents in the same export (2324s, 5408s, 2601s — 40–90 min) are
the ones this most affects: sessions that got away, with no checkpoint.

## 2. Why now / what already exists

**T12 already plumbed the parameter and stopped.** This is not a greenfield
feature:

- `OutstandingIntent {clientId, text, declaredAt}` — `lib/main.dart`, defined,
  documented, never constructed.
- `IntentCaptureScreen.outstandingIntents` — parameter exists, defaults to
  `const []`, never rendered.
- `_OverlayRootState.build()` passes `const []` with a comment saying nothing
  populates it yet.

Original intent is recorded in `docs/erd/sprint4-app-shell-plan-2026-07-23.md`
§7.1: *"prompt again with the previous bubble's text differentiated, so the user
can mark it done or add a second intent."*

## 3. Scope

**In scope:** showing the outstanding intent on the capture screen and letting
the user choose between continuing it, replacing it, or declaring no intent.

**Out of scope (deliberately):**
- **The timer.** Next piece of work; this design must not block it (§8).
- **Multiple simultaneous intents.** `outstandingIntents` is a `List` and stays
  one, so the shape doesn't have to change later — but N>1 is not built.
- **Prompting on *every* unlock.** See §5 — triage stays.

## 4. Design

### 4a. The decision point

On unlock with an outstanding intent, and if triage allows (§5), show the
capture screen with the outstanding intent rendered above the presets:

```
  Still: "Order food"           started 12 min ago
  [ Continue ]  [ Something else ]
  ──────────────────────────────
  <existing presets / custom field / Just Like That>
```

- **Continue** → close the capture screen, restore the bubble unchanged. No new
  `intent_log` row; the existing `open` row is untouched.
- **Something else** → collapses to the normal capture flow already on screen;
  the old intent is resolved per §4c and the new declaration proceeds exactly as
  today.
- **Just Like That** → existing `no_intent` path. Open question §9.2: does this
  leave the old intent outstanding, or resolve it?

### 4b. Where the data comes from

The overlay isolate **cannot touch `sqflite`** (`CLAUDE.md` §14). It must arrive
over the existing config relay:

1. New `IntentStore.openIntents({int limit})` — `SELECT … WHERE status='open'
   ORDER BY declared_at DESC`. No such query exists today.
2. `_replyActivePresetsToOverlay()` rides outstanding intents on the **same
   message** as presets — same reasoning as `manual` already does: a second,
   presets-less message on that port would be misread as "zero active presets"
   (see that function's doc).
3. Overlay's config listener populates `_outstandingIntents`, passed into
   `IntentCaptureScreen`.

No new port, no new relay direction, no plugin calls added.

`sweepOpenToAbandoned()` runs at background-engine start, so `open` rows from a
dead process are already reclassified — `openIntents()` returns only genuinely
live ones. **This must stay true**; if the sweep ever regresses, this feature
starts showing ghosts.

### 4c. Resolving the replaced intent

Choosing "Something else" ends the old intent without completing it. The
existing `status` enum is `open | done | abandoned` (`docs/DATA_MODEL.md`).
`abandoned` is semantically closest, **but it currently means "lost to process
death"** and is written by the startup sweep. Overloading it would make the
"abandoned" metric ambiguous — it would no longer distinguish "the app lost it"
from "the user consciously moved on."

**Recommendation:** add `status='replaced'` rather than overloading. It is a
distinct, meaningful user action and one of the more interesting behavioural
signals this app can capture (how often do people abandon a stated intent for a
different one?). Schema v3 migration, one new enum value. Open question §9.1.

## 5. Triage — this must NOT become "prompt on every unlock"

`CLAUDE.md` §9 explicitly warns against prompting on every unlock (friction
fatigue), and §10 records the PNAS *one sec* finding that the deliberation
prompt is the weakest active ingredient. There is also direct project
experience: the 50% probability default read as "broken" to testers and was
changed to 100% + cooldown.

A continue/new question on *every* unlock — including 20-second ones (the export
has real 2s, 7s, 41s sessions) — is exactly the nagging §9 warns about.

**Design: the outstanding-intent prompt is subject to the same triage as a
normal prompt.** Cooldown applies. Re-unlocking 30 seconds later does not
re-ask; the bubble simply stays up as today.

This yields three states rather than today's two:

| Situation | Today | After |
|---|---|---|
| No outstanding intent, triage passes | prompt | prompt (unchanged) |
| Outstanding intent, triage passes | **silent skip** | **continue/new prompt** |
| Outstanding intent, triage blocks | silent skip | silent skip (unchanged) |

`skip_reason='overlay_active'` should stay for the third row, and a new
`SkipReason.continued` (or a `prompt_shown` variant) is needed for "we asked and
they continued" so the two are distinguishable in analysis.

## 6. Engine / state changes

The capture screen and the bubble are the **same overlay window**, so showing
this prompt means closing the bubble and reopening it if the user continues.

- Background: `_showCaptureScreen`'s `_overlayIsActive` branch gains a path that
  presents capture *instead of* returning early, when `_activeOverlayKind ==
  bubble` and an outstanding intent exists and triage passes.
- Overlay: `_mode` transitions `bubble → capture → bubble` on Continue. The
  existing widget state (`_intentText`, `_intentClientId`, `_declaredAt`) must be
  **preserved**, not reset, so Continue restores the same intent — unlike
  `_dismissBubble`, which deliberately clears it.
- **Every close/reopen in this flow must use `_closeOverlayWindow()`** and the
  `_withTimeout`-guarded `showOverlay()`. Non-negotiable — see §7.

## 7. Risks

**The primary risk: this feature's core mechanic is the exact code path that
just caused a P0.** Close-bubble → show-capture → reopen-bubble *is* the
close+reopen dance where `closeOverlay()` hung (`docs/ARCHITECTURE.md` §5). This
feature makes that path run far more often, on a schedule driven by user
behaviour rather than rarely.

Mitigations, all mandatory:
1. Ship and verify the `closeOverlay()` fix in production **first**, and let it
   soak. Do not build this on an unverified fix.
2. Every plugin call in the new flow goes through the guarded helpers.
3. A failed reopen on Continue must fall back to `_abandonLostBubble()`
   semantics — losing the bubble, never losing future prompts.

Secondary risks:
- **Friction fatigue** if triage is weakened later. §5 is load-bearing, not a
  detail.
- **Latency**: this adds a DB query to the config reply on the unlock path.
  `openIntents()` must be indexed on `status` and bounded by `limit`; it must not
  push past the ~500ms budget (`CLAUDE.md` §8).
- **Cold-start race**: same `requestPresets` retry race T11 already hit. Riding
  the existing message inherits its existing retry/`_presetsConfigReceived`
  handling — do not add a second reply path.

## 8. Timer compatibility (next piece of work)

This design should make the timer *better*, not harder: "Still on Timeline —
47 min elapsed, 15 min over" is a materially stronger question than "Still on
Timeline?". `OutstandingIntent.declaredAt` already carries what an elapsed
display needs; a timer adds a target/deadline field alongside it. No decision
here should foreclose that.

## 9. Open questions (resolve before building)

1. **`status='replaced'` vs. reusing `abandoned`** (§4c). Recommendation:
   `replaced`, schema v3. Needs a call — it's a migration.
2. **Does "Just Like That" resolve the outstanding intent?** Arguably no (the
   user said nothing about the old task), but leaving it open means the next
   unlock asks again. Leaning: leave it open, since it's still genuinely
   outstanding.
3. **Elapsed-time display** — is showing "started 12 min ago" motivating or
   shaming? This is a real behavioural-design question, and a good candidate for
   `docs/USER_INTERVIEWS.md` rather than a guess.
4. **Cooldown value for this prompt specifically** — same 1 min as a normal
   prompt, or longer? A continue/new question may tolerate less frequency than a
   fresh prompt. Also interview material.

> ⚠️ **All reasoning about frequency in this doc is derived from a single user's
> export (Dinesh, one device).** That is enough to justify building, not enough
> to fix a triage policy. Treat §5's cooldown as a starting default to be
> validated, per `docs/USER_INTERVIEWS.md`.

## 10. Task breakdown

| # | Task | Notes |
|---|---|---|
| 1 | `IntentStore.openIntents({limit})` + tests | Pure data layer, no UI. Verify on-device per §5's sqflite rule in `CLAUDE.md` §3. |
| 2 | Schema v3 `status='replaced'` + migration | Gated on §9.1. |
| 3 | Ride outstanding intents on the config reply | Extend `_replyActivePresetsToOverlay`; no new port. |
| 4 | Render in `IntentCaptureScreen` | Widget test with 0 and 1 outstanding intents. |
| 5 | Continue / Something-else handlers | Preserve vs. reset widget state (§6). |
| 6 | Background triage branch + new `SkipReason` | §5's table is the spec. |
| 7 | On-device cases in `docs/TEST_PLAN.md` | Incl. reopen-failure fallback (§7.3). |

## 11. Test plan (on-device, beyond unit/widget)

- Unlock with a live bubble, triage passing → continue/new prompt appears.
- **Continue** → same bubble returns, same text, no new `intent_log` row.
- **Something else** → old row resolves per §4c, new intent declared, one bubble.
- Unlock within cooldown → no prompt, bubble untouched (regression guard on §5).
- Lock during the continue/new prompt → capture closes, `🔵 Overlay closed
  signal received` appears, next unlock behaves normally (regression guard on the
  `closeOverlay()` hang).
- Reopen failure on Continue → bubble lost but prompts continue (§7.3).
