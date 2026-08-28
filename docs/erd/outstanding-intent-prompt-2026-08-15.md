# ERD — Outstanding-intent prompt ("continue or something else?")

> Plan doc. Scoped 2026-08-15, **not yet built**. Owner: Dinesh.
> Prerequisite: the `closeOverlay()` hang fix is **on `main`** (`0.6.3+13`).
> See §7 Risks for why that ordering was not optional — it is satisfied.

## Update log

- **2026-08-28** — **Design decisions taken by Dinesh; §4a, §4c, §5, §9 and §11
  rewritten.** (1) UI is no longer `[Continue] [Something else]` buttons — the
  outstanding intent becomes a **selectable row with a resolve affordance**,
  sitting above the presets under the existing headline (§4a). (2) Triage moves
  from a plain cooldown to a **staleness floor + re-ask backoff, both flat at
  2 min** (§5) — an escalating backoff was proposed and rejected; the reasoning
  on both sides is recorded there so it isn't re-litigated. (3) The
  `abandoned` status is **renamed, not extended** — the sweep's status gets a new
  name and `abandoned` is repurposed for the user's conscious move-on (§4c).
  (4) §11 test plan expanded substantially. Timer still out of scope, but §8 now
  carries the research summary that informs it.
- **2026-08-16** — Overlay-close hang prerequisite shipped. Next session can
  build this; do not wait on another overlay-lifecycle PR. Timer still out
  of scope.
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
the user choose between continuing it, **resolving it as done**, replacing it,
or declaring no intent. (Resolve-from-capture was added to scope 2026-08-28 with
the §4a redesign — it is a genuinely new write path, not a UI shortcut.)

**Out of scope (deliberately):**
- **The timer.** Next piece of work; this design must not block it (§8).
- **Multiple simultaneous intents.** `outstandingIntents` is a `List` and stays
  one, so the shape doesn't have to change later — but N>1 is not built.
- **Prompting on *every* unlock.** See §5 — triage stays.

## 4. Design

### 4a. The decision point

**Decided 2026-08-28.** The earlier `[Continue] [Something else]` two-button
design is dropped. "Something else" was a redundant affordance — the presets
directly below it *are* "something else," so the button added a decision layer
over a choice the screen already offered. Instead the outstanding intent becomes
one more selectable row, in the same interaction language as everything else on
the screen, with a resolve affordance attached:

```
  What are you unlocking for?

  ┌───────────────────────────────────────────┐
  │  Still · Order food        12 min    [ ✓ ]│   row tap → continue
  └───────────────────────────────────────────┘   ✓ tap  → mark done
  ─────────────────────────────────────────────
  [ Check mail ]     [ Message someone ]
  [ Book a cab ]     [ Pay someone ]
  [ Call someone ]
  <custom text field>
  [ Just Like That ]
```

Three outcomes from the top row, two of which are new:

- **Tap the row → continue.** Close the capture screen, restore the bubble
  unchanged. No new `intent_log` row; the existing `open` row is untouched.
  Logged as an unlock outcome only (§5), never as a second intent.
- **Tap the ✓ → resolve as done.** Writes `status='done'` on the existing row,
  exactly as the bubble's Done button does today, then **stays on the capture
  screen** so the user can immediately declare what they are unlocking for now.
  This is the flow's most valuable moment: the checkpoint where a 40-minute
  runaway session gets closed out honestly.
- **Tap any preset / custom text → replace.** The old intent resolves per §4c
  and the new declaration proceeds exactly as today. No extra confirmation step.
- **Just Like That** → existing `no_intent` path. Open question §9.2.

**Why the ✓ is a genuinely new capability, not just a shortcut.** Today `done`
can only be written from the bubble. Routing it from the capture screen means
the capture screen gains a *resolve* write path it has never had — a new message
type on the overlay→background relay (§4b), not a reuse of the declare path.
Treat it as new surface area, not a UI rearrangement.

**Two design hazards this shape introduces** (both are §11 test cases):

1. **Mis-tap asymmetry.** Continue and Done sit on the same row. Continue is
   cheap to undo (the bubble comes back; unlock again and re-answer). Done is
   **destructive** — it closes the intent and the bubble disappears, with no undo
   in the current UI. The ✓ therefore needs a genuinely separate hit target with
   real hit-slop, not a 24dp icon flush against a full-width tappable row. If
   comfortable separation can't be achieved in the thumb zone, prefer making ✓
   the larger target and the row-tap the more forgiving one — never the reverse.
2. **Duplicate-label ambiguity.** If the outstanding intent came *from* a preset
   ("Order food"), that same preset also renders below, so two visually similar
   pills carry different semantics (continue the existing one vs. declare a fresh
   one). Mitigation: the `Still ·` prefix plus distinct chrome on the top row,
   **and** suppressing the exact-matching preset from the list below when
   `preset_id` matches. Do not rely on chrome alone.

**Layout budget.** The capture screen's thumb-zone layout was deliberately tuned
(v0.4.1, `CLAUDE.md` §2) so presets/custom-field/Just-Like-That all sit in the
one-handed reachable zone. Adding a row above the presets eats that budget. On
the smallest supported screen the outstanding row must not push "Just Like That"
or the text field out of reach — verify, don't assume (§11h).

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

No new port, no new relay direction, no plugin calls added **for the inbound
(config) direction**.

**Outbound, the ✓ needs one new message type.** Resolving from the capture
screen is not the declare path and not the existing bubble-dismiss path, so
`intentWritePort` gains a `'resolve'` message (`{clientId, status:'done'}`) —
same relay the declare/dismiss/snooze/breadcrumb messages already use, same
fire-and-forget discipline (`unawaited`, never `await`ed — `CLAUDE.md` §3). It
must be idempotent on `clientId`: a double-tap must not write twice, and
`markDone` already no-ops on an already-resolved row, which this must preserve.

`sweepOpenToAbandoned()` runs at background-engine start, so `open` rows from a
dead process are already reclassified — `openIntents()` returns only genuinely
live ones. **This must stay true**; if the sweep ever regresses, this feature
starts showing ghosts.

### 4c. Resolving the replaced intent — `abandoned` is renamed, not extended

Declaring something new ends the old intent without completing it. The existing
`status` enum is `open | done | abandoned` (`docs/DATA_MODEL.md`), where
`abandoned` today means **"lost to process death"** and is written only by
`sweepOpenToAbandoned()` at background-engine start.

**Decided 2026-08-28 (Dinesh):** rather than adding `replaced` alongside, the
*sweep* status is renamed and **`abandoned` is repurposed for the user's
conscious move-on**. This is the semantically honest assignment — in plain
English "abandoned" is something a person does, not something a crash does — and
the sweep's status is the rarer, more technical one, so it should carry the
more technical name.

**Recommended new name for the sweep status: `lost`.** Short, honest, and
unambiguous about agency. Deliberately *not* `expired` — the timer (§8) will
need that word for "the countdown ran out," and burning it here would force an
awkward rename later. `orphaned` is accurate but jargon; `stale` collides with
§5's staleness vocabulary and would be actively confusing.

Resulting v3 enum: `open | done | abandoned | lost`.

#### Complications this rename creates — all must be handled

1. **Existing rows silently change meaning. This is the serious one.** Every
   historical `status='abandoned'` row currently means "lost to process death."
   The v3 migration **must** rewrite them — `UPDATE intent_log SET status='lost'
   WHERE status='abandoned'` — as part of the same migration that introduces the
   new value. Skipping this doesn't fail loudly; it silently re-labels history,
   and every past sweep would masquerade as a deliberate user action in the
   metric this feature exists to produce.
2. **Old CSV exports become ambiguous.** T17 exports already in Dinesh's hands
   (e.g. `why_did_i_unlock_export_2026-08-15`, the one §1 quotes) use the old
   meaning. Any export produced before the v3 cutover reads `abandoned` = lost;
   after, `abandoned` = user-replaced. Record the cutover date in
   `docs/DATA_MODEL.md` so a future analysis doesn't quietly mix the two.
3. **Call sites to sweep:** `sweepOpenToAbandoned()`'s own name (rename to
   `sweepOpenToLost()`), the status enum/parsing in `lib/intent_store.dart`,
   anything in `lib/history_screen.dart` that styles or labels status, the T17
   CSV writer, any windowed insight query that buckets by status, and every test
   asserting on the literal `'abandoned'`.
4. **Migration is one-way and unguarded by tests unless written.** Add a test
   that builds a real v2 DB with `abandoned` rows, migrates, and asserts they are
   now `lost` and that no row was left on the old value (§11g).

**Why do it now rather than live with `replaced`:** the cost scales with data
volume and export count. At 29 testers and ~2 weeks of production data this is a
cheap correction; at 10k users with people's exports in the wild it is not. The
alternative (`replaced` alongside a mis-named `abandoned`) is permanently
confusing for the exact metric this feature is built to produce.

## 5. Triage — this must NOT become "prompt on every unlock"

`CLAUDE.md` §9 explicitly warns against prompting on every unlock (friction
fatigue), and §10 records the PNAS *one sec* finding that the deliberation
prompt is the weakest active ingredient. There is also direct project
experience: the 50% probability default read as "broken" to testers and was
changed to 100% + cooldown.

A continue/new question on *every* unlock — including 20-second ones (the export
has real 2s, 7s, 41s sessions) — is exactly the nagging §9 warns about.

**Design (revised 2026-08-28): two independent time gates, both must pass.**
The earlier "same triage as a normal prompt" wording was insufficient, and
worth spelling out why, because the failure it hides is subtle.

The normal cooldown is measured from the **last event** (last prompt or
declaration), which conflates two things that need to be reasoned about
separately here: *how old is this intent* and *how recently did we ask about
it*. Both currently default to 2 minutes, so they behave similarly today — but
they anchor to different events, and keeping them distinct matters for
correctness and for tuning them apart later:

Two distinct questions, two distinct gates:

| Gate | Question it answers | Default | Prevents |
|---|---|---|---|
| **Staleness floor** | Has this intent been open long enough to be worth questioning? | **2 min** (Dinesh) | Asking "still ordering food?" 20 seconds after they said "order food" — the most obviously absurd case |
| **Re-ask backoff** | Have we already asked about *this* intent recently? | **2 min, flat** (see below) | Nagging across an unlock *burst* — several unlocks in quick succession |

Both must pass. Staleness alone is not enough: once an intent crosses the floor
it stays stale forever, so a staleness-only gate would prompt on **every**
subsequent unlock — including the bursts where someone unlocks four times in
ninety seconds. The backoff exists to collapse those bursts to one ask, not to
make the app go quiet on aging intents.

#### Backoff shape: flat, same value as the floor (decided 2026-08-28)

An escalating backoff (5 → 10 → 20 → 40 min) was proposed and **rejected**.
Dinesh's argument, which holds: the probability that a declared task has
actually been *completed* rises with elapsed time, so the checkpoint gets more
valuable as the intent ages, not less. Escalating backoff has the perverse
property that **the longer the bubble is wrong, the less often the user is told**
— backwards for what is fundamentally a data-quality problem, and corrosive to
the bubble's meaning, which `CLAUDE.md` §10 puts at the centre of the product
thesis.

Second argument, equally decisive: escalating backoff optimises for long-open
intents persisting — the exact situation this feature exists to eliminate. The
40–90 minute sessions in §1 exist *because nothing was asking*.

**Decision: staleness floor and re-ask backoff are both `2 min`,** as a single
named tunable constant rather than a hardcoded literal (same treatment as
`cooldown`/`probability`, so it can move without a code change and could surface
in Settings later if testers split on it).

**The honest counter-argument, recorded so it isn't re-litigated from scratch.**
The quantity that actually governs "ask now?" is not cumulative completion
probability but the *conditional* probability of completion since the last ask —
roughly a hazard rate, which for most tasks is highest early and declines, since
an intent still open at 90 minutes is selected for being genuinely long-running.
Two real effects pull opposite ways:

- `P(completed since last ask | still open)` — **declines** with age
- `P(bubble is currently wrong)` — **rises** with age and stays high

Flat cadence optimises the second. That is a deliberate product call, not an
oversight. It is also empirically checkable post-ship (§11j).

**Snooze is the escape hatch, not an algorithm.** For a genuinely long task, a
2-minute cadence needs a way out — and one already exists: continue → the bubble
returns → snooze it. The user controls the backoff rather than a curve guessing
on their behalf, which matches how every other frequency control in this app
works. No new affordance on the row (which would worsen §4a.1's mis-tap risk).

**If it proves too chatty, raise the one constant.** Do not re-introduce
escalation machinery — see the complexity note under "Where 'when did we last
ask?' is stored" for what that costs on the unlock path.

#### Probability does NOT apply to this prompt

The normal triage ANDs cooldown with a probability gate. **Recommend excluding
the continue-prompt from the probability gate entirely.** Two reasons: the
project already learned that probabilistic skipping reads as "broken" to testers
(the 50% default was changed to 100% for exactly this, `CLAUDE.md` §3), and a
checkpoint on an intent the user can *see* is still outstanding is far more
jarring to skip randomly than a fresh prompt is. Randomness fights habituation
on fresh prompts; here it just looks like a bug.

#### Existing user settings still outrank this prompt

Excluding the probability gate (above) must **not** become "this prompt ignores
the user's settings." Two existing controls are explicit statements of intent
and must suppress the continue-prompt exactly as they suppress a normal one:

- **Master prompt toggle off** (`HomeScreen` switch → `_shouldPrompt()`). If the
  user has turned prompting off, an outstanding intent does not earn an
  exception.
- **Probability set to `Never` (0%)**. This is the subtle one: §5 says the
  probability *gate* doesn't apply, but a user who picked "Never" has said
  "don't prompt me," not "prompt me less randomly." Treat 0% as a hard off
  switch for this prompt too, distinct from treating 25–75% as a dice roll.
- **Quiet hours**, for the same reason.

Getting this wrong produces the worst possible bug class for a wellbeing app:
a user who explicitly disabled prompting starts being prompted again.

#### Where "when did we last ask?" is stored

**Derive it, don't store it.** `unlock_log` already records every unlock with an
outcome, so the last continue-prompt time is `SELECT MAX(...) FROM unlock_log
WHERE <new outcome marker>`. This avoids a schema column purely for bookkeeping.
Costs: the query sits on the unlock path, so it must be indexed and bounded
alongside `openIntents()` (§7 latency budget), and it must be robust to the row
being absent (first ever ask).

With a **flat** backoff this is a single timestamp comparison — one `MAX()`, one
subtraction. Nothing to count, nothing to reset, and it survives process death
for free because it is derived from durable rows rather than in-memory state.

This simplicity is a large part of why flat won. An escalating backoff would
have needed the *count* of prior asks for the current intent, which drags in a
bounded-by-`declared_at` query rather than a plain `MAX()`, correct reset
semantics on a new intent, counter robustness across restarts, and clock-change
behaviour on a counter rather than a single timestamp — several extra failure
modes on the ~500ms critical unlock path, bought with a number neither party
could defend from first principles.

Because N=1 (§3), "last time we asked about *this* intent" and "last time we
asked at all" are currently equivalent. Still bound the query by the open
intent's `declared_at` so the semantics stay correct if N>1 ever ships.

This yields four states rather than today's two:

| Situation | Today | After |
|---|---|---|
| No outstanding intent, normal triage passes | prompt | prompt (unchanged) |
| Outstanding intent, **younger than staleness floor** | silent skip | silent skip (`overlay_active`) |
| Outstanding intent, stale, **within re-ask backoff** | silent skip | silent skip (new reason) |
| Outstanding intent, stale, backoff elapsed | **silent skip** | **continue prompt** |

`skip_reason='overlay_active'` stays for row 2. Row 3 needs its own reason
(`SkipReason.continueBackoff` or similar) so "we deliberately stayed quiet" is
distinguishable in analysis from "the intent was too fresh." A further outcome
marker is needed for "we asked and they continued" (§4a) — the backoff derives
its timestamp from it (§5), and §11j's continue-vs-resolve ratio is unmeasurable
without it.

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
- Overlay, **✓ (resolve) path**: state must be *cleared* (opposite of Continue),
  the `'resolve'` relay message sent, and the screen must **stay in capture
  mode** rather than closing — the user still has to answer the original
  question. The outstanding row disappears from the screen on success, leaving a
  plain capture screen. If the user then locks or backs out without declaring,
  the result is a resolved intent and no new one, which is correct and needs no
  special handling.
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

### 8a. What the research actually says about timers (surveyed 2026-08-28)

Asked because the timer is the product's stated differentiator (`CLAUDE.md`
§10) and it would be bad to build it on folk wisdom. Summary: **the evidence
supports self-set deadlines as a commitment device, and warns against the
countdown as a live pressure display.** Those are two separable features and
the research pulls them in opposite directions.

**Supportive — deadlines as precommitment.** Ariely & Wertenbroch (2002),
*Procrastination, Deadlines, and Performance: Self-Control by Precommitment*,
Psychological Science, is the closest well-established result. Findings: people
*will* self-impose costly deadlines, and doing so *does* improve performance
over having no deadline — but they set them **suboptimally**, performing worse
than participants given evenly-spaced external deadlines. Direct product
reading: offering a deadline is well-founded, and **suggesting sensible
durations is not paternalism — it is correcting a documented failure mode.** A
free-text "how long?" field with no guidance is the version the research says
underperforms.

**Cautionary — the visible countdown.** The time-pressure literature is
consistently double-edged: time pressure reliably raises measured stress, speeds
task completion, and degrades quality via shallower, more heuristic processing.
Countdown displays specifically show context-dependence — they help
prioritisation and sustained engagement in some settings, and in others (the
exam-timer studies) distract and raise anxiety. Effects also vary by task
difficulty.

**What this implies for Beacon specifically:**

1. **Separate the deadline from the countdown display.** Setting "20 minutes"
   is the well-supported part. Rendering a live ticking number in a persistent
   always-on-top bubble is the part the literature is uneasy about — and Beacon's
   bubble is far more inescapable than an exam clock. Consider shipping the
   deadline with a **coarse** visual state (calm → nearing → over) rather than
   live seconds, and treat precise-countdown as a separate, later, opt-in call.
2. **This cuts against the existing spec.** `docs/PRD.md` Flow 3 currently
   describes "visual urgency cues"/"visual states as time runs low." That's
   compatible with coarse states; it is *not* a mandate for a ticking clock. Worth
   an explicit decision rather than defaulting to seconds because it's easy.
3. **The timer must be optional and non-punitive.** The speed-accuracy tradeoff
   finding means a timer on a task that shouldn't be rushed makes outcomes worse,
   not better. "Order food" benefits; "call Mum" does not.
4. **Suggest durations, don't just accept them.** Per Ariely & Wertenbroch's
   third finding — offer a few sensible presets per intent type rather than a
   blank field.
5. **Over-run is the interesting event, not expiry.** §8's own framing ("15 min
   over") is better supported than a hard expiry alarm: it's a checkpoint, not
   time pressure during the task.

**Confidence and gaps.** Ariely & Wertenbroch is a solid, well-cited primary
source. The time-pressure material is a broad literature summarised at survey
level here, not a single decisive study, and **none of it is specific to
phone-use interventions or always-on overlays** — the closest domain-specific
evidence remains the PNAS *one sec* trial already cited in `CLAUDE.md` §10.
Treat §8a as enough to shape the design questions, not enough to settle them;
the over-run-vs-countdown call is good `docs/USER_INTERVIEWS.md` material.

Sources: [Ariely & Wertenbroch 2002 (PDF)](https://web.mit.edu/ariely/www/MIT/Papers/deadlines.pdf) ·
[PubMed record](https://pubmed.ncbi.nlm.nih.gov/12009041/) ·
[Time pressure on procedural performance, scoping review 2025](https://journals.sagepub.com/doi/10.1177/10711813251369783) ·
[Clock timing & visual search under time constraint](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2024.1369920/full) ·
[APS: self-imposed deadlines don't stop procrastination](https://www.psychologicalscience.org/news/self-imposed-deadlines-dont-stop-procrastination-heres-what-might.html)

## 9. Open questions

### Resolved 2026-08-28

1. ~~**`status='replaced'` vs. reusing `abandoned`**~~ — **Decided: neither.**
   Rename the sweep status to `lost` and repurpose `abandoned` for the user's
   conscious move-on. Full reasoning and the four complications this creates in
   §4c. Still a schema v3 migration, and the history-rewrite step is mandatory.
5. ~~**Two-button `[Continue] [Something else]` layout**~~ — **Decided:** replaced
   by the selectable-row-plus-✓ design in §4a.

### Still open

2. **Does "Just Like That" resolve the outstanding intent?** Unchanged from
   2026-08-15. Arguably no (the user said nothing about the old task), but
   leaving it open means the next unlock asks again. Leaning: leave it open,
   since it is still genuinely outstanding. **Note the new interaction:** with
   §4a's ✓ present, the user now has an explicit way to say "that one's done" —
   which strengthens the case for Just Like That leaving it alone, since
   ambiguity now has a dedicated resolution affordance right above it.
3. **Elapsed-time display** — is showing "12 min" motivating or shaming? Real
   behavioural-design question; `docs/USER_INTERVIEWS.md` material rather than a
   guess. §8a's over-run finding leans toward showing it, but that evidence is
   about deliberate deadlines, not passive elapsed time — do not over-read it.
6. **The actual value of the 2-min constant** (§5). Escalating-vs-flat is
   **decided** (flat, §5). The remaining question is only whether 2 minutes is
   the right number — it is a judgement call from one user's export, and the
   binding constraint in practice is unlock *frequency*, not the constant. Post-
   ship measurement (§11j) settles this better than any amount of reasoning;
   the fix if it is chatty is raising one tunable, not adding machinery.
7. **Does the ✓ need an undo?** Resolve-as-done is destructive and has no undo
   anywhere in the app today (the bubble's Done button has the same property, so
   this is not a new asymmetry — but this design puts the affordance somewhere
   far easier to hit by accident). A brief SnackBar-style undo inside the capture
   screen is cheap; decide before shipping rather than after a tester reports it.
8. **Should the ✓ appear at all when the intent is very fresh?** If the staleness
   floor is 2 min, the prompt never shows for younger intents anyway — so this is
   moot *unless* the floor is later lowered. Recorded so the coupling isn't lost.

> ⚠️ **All reasoning about frequency in this doc is derived from a single user's
> export (Dinesh, one device).** That is enough to justify building, not enough
> to fix a triage policy. Treat §5's floor and backoff as starting defaults to be
> validated, per `docs/USER_INTERVIEWS.md`.

## 10. Task breakdown

Ordered so each step is independently verifiable. Steps 1–2 are pure data layer
and can land and soak before any UI exists.

| # | Task | Notes |
|---|---|---|
| 1 | `IntentStore.openIntents({limit})` + tests | Pure data layer, no UI. Index on `status`. Verify on-device per the sqflite rule in `CLAUDE.md` §3 — a clean `flutter test` does **not** prove the Android DB path. |
| 2 | **Schema v3: rename `abandoned`→`lost`, repurpose `abandoned`** + migration | §4c. Includes the mandatory history-rewrite `UPDATE`, the `sweepOpenToAbandoned`→`sweepOpenToLost` rename, and every call site in §4c.3. Land this **alone**, before any UI. |
| 3 | Ride outstanding intents on the config reply | Extend `_replyActivePresetsToOverlay`; no new port, no second message (§4b). |
| 4 | `'resolve'` message on `intentWritePort` + background handler | New outbound type (§4b). Fire-and-forget, idempotent on `clientId`. |
| 5 | Render the outstanding row in `IntentCaptureScreen` | §4a. Includes duplicate-preset suppression and hit-target separation. Widget tests with 0 and 1 outstanding intents. |
| 6 | Continue / ✓-resolve / replace handlers | Preserve vs. clear widget state (§6) — the two paths differ deliberately. |
| 7 | Background triage: staleness floor + flat backoff + new `SkipReason`s | §5's four-state table is the spec. Both gates are one named tunable (2 min), not literals. Derive last-ask from `unlock_log` — a single `MAX()`, no new column, no counter. |
| 8 | Breadcrumbs for the new decisions | `ProblemReportLog.recordBreadcrumb` via the existing relay, so a problem report shows continue/resolve/replace decisions. |
| 9 | On-device cases in `docs/TEST_PLAN.md` | §11 is the source list. Incl. reopen-failure fallback (§7.3). |

## 11. Test plan

Expanded 2026-08-28. Organised by **what breaks it**, not by feature area,
because the interesting failures here are in the seams (isolate relay, overlay
lifecycle, migration) rather than in the happy path. Rows marked 🔴 are the ones
that would ship a real regression if skipped.

Numbering is local to this doc; on-device rows get real `docs/TEST_PLAN.md`
case numbers when built (task 9).

### 11a. Data layer — automated (`flutter test`)

| # | Case | Expected |
|---|---|---|
| A1 | `openIntents()` with zero open rows | Empty list, no throw |
| A2 | `openIntents()` with one open row | That row, with `clientId`/`text`/`declaredAt` intact |
| A3 | `openIntents()` ignores `done`/`abandoned`/`lost` rows | Only `open` returned |
| A4 | `openIntents(limit: n)` bound is respected | Never more than `n`; newest first (`declared_at DESC`) |
| A5 | 🔴 `openIntents()` after `sweepOpenToLost()` | Returns empty — swept rows must not resurface as ghosts (§4b) |
| A6 | `'resolve'` → `markDone` writes `status='done'`, sets `completed_at` | Matches the bubble-Done path exactly |
| A7 | 🔴 `'resolve'` twice on the same `clientId` | Second is a no-op; `completed_at` unchanged from the first (idempotency, §4b) |
| A8 | `'resolve'` on an unknown `clientId` | No-op, no throw, no row created |
| A9 | 🔴 `'resolve'` on an already-`abandoned` row | No-op — must **not** resurrect a resolved row (existing invariant, `intent_store_test.dart` already guards this class) |
| A10 | Replace path writes `status='abandoned'` on the old row + a new `open` row | Two rows, one open |
| A11 | Last-ask derivation query returns null on a fresh DB | Backoff treats "never asked" correctly, no crash |
| A12 | Last-ask derivation is bounded by the open intent's `declared_at` | A previous intent's asks don't leak into the current intent's gate (§5) |

### 11b. Schema v3 migration — automated 🔴

The whole of §4c.1 lives or dies here. Build a **real v2 DB file** (as
`intent_store_test.dart` already does for v1→v2), don't fake it.

| # | Case | Expected |
|---|---|---|
| B1 | 🔴 v2 DB with `abandoned` rows → migrate | Every one becomes `lost`. Zero rows left on `abandoned` |
| B2 | 🔴 Post-migration, `abandoned` is writable with the new meaning | A replace writes `abandoned`; it is distinguishable from the migrated `lost` rows |
| B3 | v2 DB with **zero** `abandoned` rows | Migration succeeds, no-ops cleanly |
| B4 | v2 DB with **only** `abandoned` rows | All convert; DB still opens |
| B5 | v2 DB with a mix of all statuses | `open`/`done` untouched; only `abandoned`→`lost` |
| B6 | Migration is idempotent / not re-run on an already-v3 DB | Version guard works; `abandoned` rows written *after* migration are not re-swept to `lost` on next open |
| B7 | 🔴 Fresh install (no prior DB) | Creates v3 directly, both statuses present in the enum, no migration path executed |
| B8 | Every enum parse/serialise round-trips all four values | `open \| done \| abandoned \| lost` |

### 11c. Widget — automated

| # | Case | Expected |
|---|---|---|
| C1 | `outstandingIntents: []` | Screen renders exactly as today — no row, no divider, no layout shift |
| C2 | One outstanding intent | Row renders above presets with `Still ·` prefix, text, elapsed, ✓ |
| C3 | 🔴 Row tap and ✓ tap fire **different** callbacks | The core mis-tap risk (§4a.1) — assert they are not wired to the same handler |
| C4 | 🔴 Duplicate-preset suppression | Outstanding intent with `preset_id` X → preset X absent from the list below (§4a.2) |
| C5 | Outstanding intent with a *custom* (non-preset) text | No suppression; all presets still render |
| C6 | Very long intent text (200+ chars) | Ellipsis/wrap, no overflow exception, ✓ stays reachable |
| C7 | Elapsed formatting boundaries | `<1 min`, `1 min`, `59 min`, `1 hr 2 min`, `25 hr` all render sanely |
| C8 | 🔴 Negative elapsed (device clock moved backwards) | Does **not** render "-8 min" or throw; clamps to something sane (§11g G7) |
| C9 | ✓ tapped → row disappears, presets remain, screen stays open | Per §6 resolve path — screen must not close |
| C10 | All presets disabled + one outstanding intent | Row still renders; custom field + Just Like That still usable |

### 11d. On-device — core user paths

| # | Case | Expected |
|---|---|---|
| D1 | Unlock with a live bubble, intent stale, backoff elapsed | Continue prompt appears with the correct intent text |
| D2 | 🔴 **Tap the row (continue)** | Same bubble returns, same text, same position. **No new `intent_log` row.** Existing `open` row untouched, `declared_at` unchanged |
| D3 | 🔴 **Tap ✓ (resolve)** | Old row → `done` with `completed_at`. Screen **stays open** on a plain capture screen. Bubble does not reappear |
| D4 | ✓ then declare a new intent | One `done` row + one new `open` row; exactly one bubble, showing the new text |
| D5 | ✓ then lock without declaring | One `done` row, no new row, no bubble. Next unlock behaves as a normal fresh prompt |
| D6 | 🔴 **Tap a preset (replace)** | Old row → `abandoned` (new meaning), new `open` row, exactly **one** bubble with the new text |
| D7 | Type custom text (replace) | Same as D6 via the custom path |
| D8 | **Just Like That** | Per §9.2 — currently: old intent stays `open`, `no_intent` row written, bubble returns unchanged. Assert whichever way §9.2 lands |
| D9 | Back out / no interaction, then lock | Nothing written; intent still `open`; bubble state correct on next unlock |

### 11e. On-device — triage and timing (§5)

| # | Case | Expected |
|---|---|---|
| E1 | 🔴 Declare intent, lock, unlock **within** the staleness floor | **No prompt.** `skip_reason='overlay_active'`. This is the "absurd case" the floor exists to kill |
| E2 | Unlock just **after** the staleness floor | Prompt appears |
| E3 | 🔴 Prompt shown, continue, unlock again immediately | **No prompt** (re-ask backoff). Bubble untouched |
| E4 | 🔴 **Unlock burst** — 4 unlocks within 90s, intent stale | Exactly **one** prompt, not four. This is the backoff's actual job (§5) |
| E4b | Unlock repeatedly across a long session at >2 min intervals | A prompt each time, by design. Count them and record the number — this is the input to the §11j "is 2 min too chatty" question, not a pass/fail |
| E5 | 🔴 Backoff survives a process restart | Force-stop mid-session, unlock immediately → still suppressed if within 2 min of the last ask (derived from `unlock_log`, not in-memory state, §5) |
| E6 | New intent declared → gates re-anchor | Staleness measures from the **new** intent's `declared_at`; the old intent's asks don't suppress the new one |
| E7 | 🔴 **Master prompt toggle OFF** + outstanding intent | **No prompt, ever.** The worst-bug-class guard (§5) |
| E8 | 🔴 **Probability = Never (0%)** + outstanding intent | **No prompt.** Distinct from 25–75%, which does not gate this prompt |
| E9 | Probability = 50% + outstanding intent | Prompt appears **deterministically** — probability does not apply (§5) |
| E10 | 🔴 **Quiet hours active** + outstanding intent | No prompt |
| E11 | Very short unlock (2–7s) during backoff | No prompt; no spurious rows |
| E12 | Each suppression writes its **own** `skip_reason` | `overlay_active` (too fresh) vs. the new backoff reason are distinguishable in the export (§5 table) |

### 11f. On-device — overlay lifecycle 🔴 (the P0-adjacent surface)

§7 names this as the primary risk: this feature runs the close→reopen dance far
more often than anything before it. Every row here is a regression guard on a
bug that has **already happened once**.

| # | Case | Expected |
|---|---|---|
| F1 | 🔴 Lock the phone **while the continue prompt is showing** | Capture closes, `🔵 Overlay closed signal received` in logcat, next unlock behaves normally (guards the `closeOverlay()` hang) |
| F2 | 🔴 Reopen failure on Continue | Falls back to `_abandonLostBubble()` semantics: bubble lost, `_overlayIsActive` reset, **future prompts still work** (§7.3). Verify by forcing the timeout path |
| F3 | 🔴 Rotate the device while the prompt is showing | `onOrientationChanged` → close+reopen; prompt survives or closes cleanly. No stuck `_overlayIsActive`, no doubled window |
| F4 | Open the app from the launcher while the prompt is up | Main UI engine attaching does not hijack the relay (the `WindowSetup.messenger` hazard, `ARCHITECTURE.md` §5). Prompt still responds |
| F5 | 🔴 Rapid lock/unlock cycling (5+ times fast) | Exactly one overlay window at any time; no orphaned bubble; no stuck flag; no crash |
| F6 | Continue tapped twice rapidly | One reopen, one bubble |
| F7 | 🔴 After 20+ continue/replace cycles in one session | No engine leak, no memory growth trend, prompts still appear. The cached-overlay-engine staleness class (`_presets` going stale) must not reappear for `outstandingIntents` |
| F8 | Notification shade item during the prompt | Overlay FGS notification shows correct content, Beacon icon (case 109 regression guard) |

### 11g. On-device — process, OS and system edge cases

| # | Case | Expected |
|---|---|---|
| G1 | 🔴 Force-stop with an intent open, reopen app, unlock | Sweep marks it `lost` (not `abandoned`); **no ghost row** offered in the prompt (§4b) |
| G2 | Reboot with an intent open | Same as G1 via `BootReceiver` path |
| G3 | 🔴 Direct-boot unlock (first unlock after reboot, before credential storage unlocks) | `_ensureIntentStore()` retry still works; prompt either appears correctly or is skipped cleanly — never crashes, never writes a malformed row |
| G4 | OEM background-kill mid-session (Xiaomi/Vivo/Oppo), then unlock | Degrades to G1 behaviour, not a stuck state |
| G5 | Doze / battery saver during a long open intent | Prompt appears on next real unlock; no wakelock added by this feature |
| G6 | App update (`UpdateReceiver`) with an intent open | Existing update path still handles it; no new lost-write window |
| G7 | 🔴 **Device clock moved backwards** while an intent is open | Elapsed does not go negative in UI (C8); staleness floor does not permanently block or permanently pass; no crash |
| G8 | Device clock moved **forwards** (or DST/timezone change) | A 2-minute-old intent doesn't suddenly read as 3 hours; backoff doesn't skip to the cap. Document actual behaviour if not fully fixable |
| G9 | Storage full / DB write fails on resolve | Fire-and-forget relay doesn't hang the UI; error reaches `ProblemReportLog`; bubble state stays coherent |
| G10 | 🔴 Background engine not yet ready when ✓ is tapped (cold start race) | Relay message dropped → the row stays `open`. Must not silently look resolved in the UI while the DB disagrees. Prefer optimistic-UI-plus-retry or no-UI-change-until-confirmed; decide and test |

### 11h. Layout, accessibility, device matrix

| # | Case | Expected |
|---|---|---|
| H1 | 🔴 Smallest supported screen (low-end, ≤3GB, small display) | Outstanding row does **not** push the custom field or Just Like That out of the thumb zone (§4a layout budget) |
| H2 | Large system font scale (accessibility sizing) | Row wraps/truncates gracefully; ✓ still hittable; no overflow |
| H3 | 🔴 ✓ hit target vs. row hit target measured on-device | Real separation; deliberate mis-tap attempts at the boundary land where intended more often than not (§4a.1) |
| H4 | TalkBack / screen reader | Row and ✓ announce as **two distinct** actions with meaningful labels ("Continue: Order food" / "Mark Order food done"), not one blob |
| H5 | Keyboard open (custom text field focused) with the row present | Row scrolls/collapses sensibly; keyboard doesn't shove content off-screen (the v0.4.1 fix must not regress) |
| H6 | Landscape | Row renders; no overflow; F3 lifecycle still clean |
| H7 | Low-end device, `--release` | Prompt still appears within the ~500ms unlock budget (`CLAUDE.md` §8) **including** the two new DB queries (§7 latency) |

### 11i. Adversarial / unusual user behaviour

| # | Case | Expected |
|---|---|---|
| I1 | Double-tap ✓ as fast as possible | One `done` write (A7 on-device) |
| I2 | Tap ✓ then immediately lock before the relay lands | Write completes or is cleanly lost — never a half-state where UI and DB disagree permanently |
| I3 | Tap row and ✓ near-simultaneously (two fingers) | One outcome wins deterministically; no double-write, no crash |
| I4 | Declare → replace → replace → replace rapidly | One `open` row at the end; N−1 `abandoned`; exactly one bubble |
| I5 | Leave an intent open for 24h+ | Prompt still correct; elapsed formats sanely (C7); backoff sits at the cap |
| I6 | Delete/disable the preset an open intent came from (Manage options), then unlock | Row still renders the stored text; suppression logic doesn't crash on a missing preset |
| I7 | Rename that preset, then unlock | Row shows the **stored intent text**, not the renamed preset label |
| I8 | Restore-defaults on presets while an intent is open | No crash; row unaffected |
| I9 | Export CSV mid-flow (T17) | Export includes the new statuses correctly; header/meaning matches §4c.2 |
| I10 | Report a problem after using the flow | Breadcrumbs show continue/resolve/replace decisions (task 8), not just exceptions |

### 11j. Post-ship data sanity (not a pre-merge gate)

Once live, confirm on a real export that the feature is producing the signal it
was built for — this is the actual success criterion, and it can only be checked
after a few days of use:

- `abandoned` (new meaning) rows appear and are plausibly counted — this is the
  "how often do people consciously move on?" metric §4c justifies the rename for.
- `lost` rows are **rare**. A spike means the sweep is firing more than expected
  (i.e. a process-death problem), not that users changed behaviour.
- The `overlay_active` skip share drops meaningfully from the 48/109 baseline
  in §1 — that number was the motivation, so it is the number to re-measure.
- 🔴 **Prompts per long session, on real usage.** This is the number that
  settles §9.6 — whether flat 2 min is right, or too chatty. Reasoning cannot
  settle it; unlock frequency is the binding constraint and it varies per person.
- 🔴 **Snooze rate on the bubble.** §5 makes Snooze the user-controlled escape
  hatch instead of an algorithmic backoff. A rising snooze rate is the clearest
  signal the cadence is too aggressive — and unlike a complaint, it arrives as
  data. If it climbs, raise the constant; do not add escalation machinery back.
- **Continue-vs-resolve ratio.** Mostly ✓ means the prompt is catching real
  stale bubbles (the feature working). Mostly Continue means it is interrupting
  genuine work, which points the same direction as a high snooze rate.
- **Long-open intents should become rarer over time.** The 40–90 min sessions in
  §1 existed because nothing was asking. If they persist at the same rate after
  shipping, the prompt is not doing its job — check before tuning the cadence.
- No rise in "Just Like That" rate — a rise would suggest the extra decision is
  being escaped rather than engaged with (the same backfire risk flagged for
  pill randomisation in `docs/BACKLOG.md`).
