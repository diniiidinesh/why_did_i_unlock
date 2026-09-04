# Beacon — Goals & Success Metrics

> **Status:** proposal, 2026-09-04. Written against the code at `main` (`0.6.4+17`).
> Nothing here is instrumented yet. §8 separates what is computable today from what
> is blocked, and §9 lists the places where the code was ambiguous and the answer
> changes the metric.
>
> Related: `docs/DATA_MODEL.md` (schema of record), `docs/PRD.md` (product),
> `CLAUDE.md` §10/§11 (strategy, monetization — both still open).

---

## 1. What the code actually supports today

This section is an audit result, not a design. Everything below was read out of the
repository; where a capability is absent it is called absent, not approximated.

### 1.1 Permissions declared (`android/app/src/main/AndroidManifest.xml`)

| Permission / feature | Declared? | Notes |
|---|---|---|
| `SYSTEM_ALERT_WINDOW` (overlay) | **Yes** | The core mechanic. Needs a manual Settings grant, plus the Android 13+ "Restricted settings" unblock on sideloads. |
| `FOREGROUND_SERVICE` + `FOREGROUND_SERVICE_SPECIAL_USE` | **Yes** | Subtypes `monitorPhoneUnlocks` (own service) and `showOverlayOnUnlock` (the overlay plugin's service). |
| `RECEIVE_BOOT_COMPLETED` | **Yes** | `BootReceiver`, `directBootAware`, listens for `LOCKED_BOOT_COMPLETED` + `BOOT_COMPLETED` + two QUICKBOOT variants. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | **Yes** | One-tap exemption dialog from the Status screen. |
| `POST_NOTIFICATIONS` | **Yes** | Only for the optional day-1 recap reminder. Not a push channel. |
| **`INTERNET`** | **No — release builds have no network permission at all** | It appears only in `src/debug/` and `src/profile/` manifests (Flutter tooling). This is the single most important fact in this document. |
| `AccessibilityService` | **No** | Never declared, no service class. Deliberate (`CLAUDE.md` §9). |
| `PACKAGE_USAGE_STATS` / usage access | **No** | So the app cannot see which app the user opens, or for how long. |
| `RECORD_AUDIO` | **No** | Voice capture is not built. |
| `android:allowBackup` | **`false`** | Intent text never enters cloud/adb backups. |

Also declared: `android.hardware.touchscreen` as **required**, which excludes
tablets/Wear/TV from Play's compatible-device list. Any "installs" number is
phone-only by construction.

### 1.2 Unlock detection

`UnlockReceiver` (registered at runtime by `UnlockListenerService`, a `specialUse`
foreground service) listens for two system broadcasts:

- `ACTION_USER_PRESENT` → `UnlockListenerService.onPhoneUnlocked(w,h)` → `MethodChannel`
  `com.whydidiunlock/unlock` → the **persistent background Flutter engine**.
- `ACTION_SCREEN_OFF` → `onPhoneLocked()` → same channel.

Three consequences that matter for every metric in this document:

1. **"Unlock" means an authenticated user-present event, not a screen-on.** Screen
   wakes, notification peeks, and unlocks on a device with no lockscreen are not
   observed. A user with no screen lock effectively generates no data.
2. **Every observed unlock is logged; not every unlock is prompted.** The prompt
   decision has nine distinct skip reasons (`SkipReason`): `promptsDisabled`,
   `cooldown`, `probability`, `overlayActive`, `noPermission`, `invalidScreenSize`,
   `pluginTimeout`, `quietHours`, `snoozeEnded`. Each is written into `unlock_log`.
   This is unusually good instrumentation for a v1 and most of §5 depends on it.
3. **Unlocks that occur while the foreground service is dead are invisible, and
   leave no gap marker.** On an aggressive OEM (Xiaomi/Oppo/Vivo/realme — the target
   market) a day with 4 logged unlocks may be a quiet day or a killed service. The
   data cannot tell those apart. See §9-Q5; this is the largest measurement hole in
   the product.

### 1.3 Intention capture

Full-screen overlay ("capture screen") with three input paths:

- **Preset tap** — DB-backed (`intent_preset`), relayed to the plugin-less overlay
  isolate over `IsolateNameServer` ports. Six defaults, max 8 enabled.
- **Custom text** — free text field.
- **"Just Like That"** — an explicit *no real reason* admission. Logged as
  `kind='no_intent'`, no bubble shown.

Written on **declaration**, not dismissal (so a crash mid-session does not lose the
row). Fields stored per event (`intent_log`): `id`, `client_id` (unique, idempotent
writes), `kind` (`intent` | `no_intent`), `source` (`preset` | `custom` | null),
**`text` (the raw intention text)**, `declared_at`, `completed_at`, `status`,
`unlock_id`, `preset_id`.

There is **no** timestamp for "prompt appeared", so time-to-answer is not recoverable.

### 1.4 Bubble / overlay lifecycle

- Declared intent → bubble, expanded (text + two actions) → collapses.
- Two actions only: **Done** (`Icons.check`) and **Snooze** (`Icons.notifications_paused`).
- **Snooze is a fixed 10 minutes, held in memory in the background isolate**
  (`_bubbleSnoozeDuration`, `_SnoozeSession`, `Timer`). It is not persisted and
  writes no row. A process death during snooze loses it silently.
- **There is no timeout or expiry.** A bubble stays up indefinitely until Done.
- **Screen lock does not dismiss the bubble** — only the capture screen closes on
  lock. An intent survives lock/unlock cycles.
- **There is no timer/countdown feature.** The bubble+timer combination described as
  the product's defensible wedge (`CLAUDE.md` §10) is **not built**. Only the bubble
  half exists.
- Abandonment is *inferred*, never observed: `sweepOpenToAbandoned()` flips lingering
  `open` rows to `abandoned` at background-engine start. So `abandoned` counts
  process restarts as much as user behaviour (§9-Q2).

### 1.5 Local persistence

**sqflite, not Room.** `lib/intent_store.dart`, schema v2, WAL, three tables:

- `intent_log` — fields above; indexes on `completed_at`, `declared_at`.
- `unlock_log` — `id`, `unlocked_at`, `prompt_shown`, `skip_reason`. Append-only.
- `intent_preset` — `label`, `sort_order`, `enabled`, `deleted_at`, `tier`,
  `allowed_packages` (unused), `created_at`.

Aggregation helpers already exist: `unlockCount`, `promptShownCount`,
`outcomeBreakdown`, `completionDurationStats` (median + mean + n), over
`InsightWindow.{today,last7Days,last30Days}`. Retention is **user-configurable**
(90d / 1y / forever) — but see §9-Q1: the setting is stored and displayed and
**never automatically enforced**; pruning only happens when the user taps a
confirm dialog in "Your data".

Settings live in `shared_preferences` via `AppSettings` (`SharedPreferencesAsync`
only, deliberately). Includes a plain `app_launch_count` integer and a
`first_launch_at` timestamp — counters, not events, and both reset with app data.

### 1.6 Analytics

**None.** No Firebase, no Crashlytics, no Amplitude/Mixpanel/Sentry, no custom
telemetry, no `http` call anywhere in `lib/`. There is no analytics SDK in
`pubspec.yaml`. The release build cannot make a network call even if code tried.

### 1.7 Anything sent off-device

Exactly three paths, all explicitly user-initiated, all outside the app process:

1. **CSV export** (`lib/export_csv.dart` → `share_plus`) — a full, lossless dump
   including an **`intent_text` column**.
2. **"Report a problem"** (`lib/problem_report.dart` → `mailto:`) — a rolling local
   error buffer plus lifecycle breadcrumbs. Breadcrumb text is gated so declared
   intent text is not included in release builds.
3. **`url_launcher`** to the privacy policy / Play listing.

Nothing is transmitted by the app itself.

### 1.8 Verdict — implemented / partial / absent

**Implemented:** unlock + lock detection surviving reboot, app update and Recents
swipe; per-unlock logging with a prompt-or-skip reason; preset/custom/no-intent
capture; persistent draggable bubble with Done and Snooze; local history, CSV
export, on-device insight cards (unlocks, prompts, outcome donut, median/mean
completion duration), a day-1 recap; user-managed presets; settings for cooldown,
probability, quiet hours, retention; onboarding + walkthrough + tooltips.

**Partial:** *abandonment* (inferred from process lifecycle, not user action);
*snooze* (works, records nothing); *retention* (configurable, not enforced);
*service survival* (restart receivers exist; OEM kills still produce silent blind
spots); *cohorting* (`first_launch_at` exists but resets with app data and has no
stable install id).

**Absent:** the timer/countdown; voice input; any completion signal other than the
user's own tap; any notion of which app was used or for how long; any publisher-side
telemetry; app-open/session events; onboarding step-level drop-off; prompt
answer-latency; permission grant/deny timeline.

### 1.9 The measurement constraint this creates

The app has good *on-device* instrumentation and **zero publisher-side visibility.**
There are exactly three planes of measurement:

| Plane | What it can show | Available today |
|---|---|---|
| **A. On-device** | Everything in §1.5, per user, in that user's own app | Yes |
| **B. Play Console** | Installs, uninstalls, D1/D7/D30 retention, crash/ANR vitals, ratings, reviews, device/country mix | Yes, no work needed |
| **C. Population-level behaviour** | Every metric in §5–§6 | **No. Requires either an opt-in aggregate channel (the open decision in `CLAUDE.md` §11) or a recruited panel that hands over exports.** |

Any metric below that lives in plane C is labelled as such. I am not proposing a
plane-B proxy for a plane-C question — that is exactly the trap in the brief.

---

## 2. Product purpose and actor goals

### 2.1 Purpose

Beacon exists to test one behavioural hypothesis:

> **Making the reason for an unlock explicit, and keeping that reason visible as a
> persistent overlay for the duration of the session, causes a person to complete
> what they picked up the phone for and end the session — instead of drifting.**

It is a solo-built, recently published, unmonetized app. The purpose is **evidence**,
not revenue and not scale. Concretely, success in the next two quarters means being
able to say one of:

- "The bubble changes behaviour for segment X, here is the evidence" → build the timer.
- "It does not, and here is why" → stop, or reposition.

The failure mode this framing exists to prevent: optimising for installs and
retention, reaching 10k users, and still not knowing whether the thing works. A
metric set that would look healthy on a habit-forming app is *actively misleading*
here (§3).

**A note the metrics must respect:** the PNAS *one sec* RCT found the deliberation
prompt is the weakest active ingredient among friction interventions, and the
product's stated wedge is bubble + timer. **The timer is not built.** So today the
product is closer to "prompt + reminder" than to its own thesis, and current metrics
can only test the weaker half. That is a finding, not a nitpick — it means a flat
result over the next quarter would *not* falsify the hypothesis.

### 2.2 User goals (value the user receives)

Retention, engagement and conversion are deliberately absent here; they are §2.3.

- **U1 — Catch myself.** Notice the reach-for-the-phone reflex at the moment it
  happens, before the session starts.
- **U2 — Be honest without penalty.** Have a way to say "no reason" that costs
  nothing and isn't scolded.
- **U3 — Finish what I came for.** Get to the end of the thing I unlocked for
  without being pulled elsewhere.
- **U4 — Leave cleanly.** End the session deliberately rather than surfacing 40
  minutes later.
- **U5 — See my own pattern truthfully.** Learn something about myself I didn't
  already know, from my own data.
- **U6 — Stay in control of the tool.** Tune or silence it without a fight; never
  feel nagged or surveilled by the thing that is supposed to help.
- **U7 — Pay no hidden cost.** No account, no data leaving the phone, no battery
  drain, no lag at unlock.

### 2.3 Business goals (solo publisher, no revenue)

- **B1 — Get a decisive answer on the hypothesis within ~2 quarters, cheaply.**
- **B2 — Specifically test the *bubble* (and then the timer), not the prompt** —
  the prompt is the commoditised part and the weakest ingredient.
- **B3 — Learn which segment it works for** (if any), well enough to aim the next build.
- **B4 — Stay published and installable** — Play policy and vitals, indefinitely.
- **B5 — Keep total maintenance load inside one person's evenings.**
- **B6 — Preserve optionality** on monetization and on the iOS decision; ship nothing
  that assumes an answer.
- **B7 — Accumulate enough credibility** (reviews, word of mouth, a working tester
  pool) to recruit the *next* cohort when there is something worth testing.

### 2.4 Other stakeholders

- **Google Play — gatekeeper.** Cares about: `SYSTEM_ALERT_WINDOW` and special-use
  FGS justification, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (heavily scrutinised),
  Data Safety accuracy, crash/ANR vitals, the Feb 2027 R8 25% optimization floor
  (currently 49%, compliant), edge-to-edge, target-SDK cadence. Play can end the
  product unilaterally; its thresholds belong in guardrails, never in tradeoffs.
- **Device OEMs — silent adversary.** Aggressive background killing decides whether
  Beacon works at all in its main market. They publish no signal; the app must
  measure its own survival.
- **The ~29 closed testers / friends — unpaid, socially costly.** Their goal is a
  working app and a short feedback ask. Burning them is irreversible; there is no
  second batch of friends.
- **Anyone who sees the bubble on the user's screen.** The bubble renders the user's
  intention text over other apps, in public. That is a real privacy surface and a
  reason never to make the expanded state more prominent by default.

---

## 3. The anti-engagement inversion (handled explicitly)

The standard consumer metric stack is wrong here, in a specific and mechanical way:

- **Every event this product generates is downstream of an unlock.** Prompts shown,
  intents declared, bubbles resolved — all of them scale with how often the user
  unlocks their phone. A user who improves generates *less* data. Any count of
  events therefore moves in the wrong direction on success and the right direction
  on failure.
- **The best possible outcome may be near-silent.** A user who unlocks 30 times a
  day instead of 90, opens the app never, and declares four intents a day is the
  product working. On a normal dashboard that user looks like churn.
- **App opens are a cost, not value.** Time in Beacon's own UI is overhead: the value
  is delivered at the lockscreen and in the overlay, not in the app.

Three rules follow, and every metric in §5–§7 obeys them:

1. **Cap per user per day.** Metrics count *users* and *days*, never events. "Users
   with an intentional day" cannot be inflated by unlocking more.
2. **Unlock volume is never a success metric — it is a counter metric.** If the NSM
   rises while median unlocks per user per day also rises, the product is failing
   and the NSM is lying. That pairing is written into §7.
3. **In-app engagement is explicitly excluded from primaries.** App opens, screen
   views, tooltip taps and notification opens are diagnostics for a specific
   onboarding change, never goals.

---

## 4. Candidate metric long list (unfiltered)

Job to be done: *"When I pick up my phone out of habit, help me either name a
purpose or put it down — and then actually finish that purpose and stop."*

Funnel stages, with candidates at each. Breadth = how many users reach it;
depth = how much value each gets. **Plane** per §1.9.

### Stage 0 — Discovery & install
1. Installs per week (B)
2. Store-listing view → install conversion (B)
3. Uninstalls within 24h / 7d (B)
4. Rating count and distribution (B)

### Stage 1 — Setup (the permission cliff)
5. Installs completing onboarding (C)
6. Installs granting overlay permission (C)
7. Installs granting battery-optimization exemption (C)
8. Installs reaching a **first answered prompt** within 24h (C) ← *activation*
9. Median steps completed before drop-off (C, blocked — see §8)
10. Installs granting overlay but never answering a prompt (C)

### Stage 2 — Survival (does the app still run?)
11. Installs with ≥1 observed unlock on ≥6 of the last 7 days (C)
12. Installs with a ≥24h gap in `unlock_log` (C)
13. Service restarts per install per week, by cause (boot / update / engine start) (C, partly blocked)
14. Observed unlocks per install per day (C) — *diagnostic and counter, never a goal*
15. Crash-free session rate, ANR rate (B)

### Stage 3 — Prompted
16. Unlocks with `prompt_shown=1` per user per day (C)
17. Skip-reason distribution — especially `noPermission`, `pluginTimeout`, `overlayActive` (C)
18. Users with any `pluginTimeout` or `invalidScreenSize` in a week (C) — pure defect signal
19. Prompts suppressed by user configuration (`quietHours`, `promptsDisabled`, low `probability`) (C)

### Stage 4 — Answered
20. Prompts answered vs. shown, per user per day (C)
21. Users with ≥1 answered prompt today (C)
22. **Users with ≥1 `no_intent` ("Just Like That") admission this week** (C)
23. Answers by source: preset / custom / no-intent (C)
24. Time from prompt shown → answered (C, **blocked**: no shown-at timestamp)
25. Prompts shown with no linked intent row = ignored prompts (C, derivable today)
26. Custom-text share of declarations (C) — depth proxy for "presets don't fit me"

### Stage 5 — Bubble present
27. Users with ≥1 bubble live per day (C)
28. Bubble lifetime, declared → resolved (C, available as `completed_at - declared_at`)
29. Snoozes per user per week (C, **blocked**: not persisted)
30. Bubbles surviving a lock/unlock cycle (C, blocked — no lock events on `intent_log`)

### Stage 6 — Resolution
31. **Users with ≥1 intent marked Done on ≥N days this week** (C)
32. Done vs. abandoned counts (C, but see §9-Q2 — `abandoned` is unreliable)
33. Median time-to-Done (C, exists)
34. **Share of Done within 5 seconds of declaring** (C) — reflexive-dismissal detector
35. Intents left `open` > 24h (C)

### Stage 7 — Behaviour change (the actual hypothesis)
36. Change in observed unlocks/day, week 4 vs. week 1, per user (C)
37. Change in `no_intent` share, week 4 vs. week 1, per user (C)
38. Change in median time-to-Done over the same window (C)
39. Users whose observed unlocks/day fell ≥20% and who still answer prompts (C)
40. Self-reported "I catch myself more often" (interviews — not a product metric)
41. Actual screen time reduced (**not measurable — no usage access. No proxy proposed.**)
42. Whether the declared intention was actually performed (**not measurable at all**)

### Stage 8 — Retention & durability
43. D1 / D7 / D30 install retention (B)
44. **Users with ≥4 intentional days in the trailing 7** (C)
45. Users still meeting (44) in week 4 / week 8 (C)
46. Users who turned prompts **off** but kept the app installed (C) — quiet quit
47. Users who reduced probability below 50% or widened quiet hours after week 1 (C)
48. Uninstalls within 48h of granting overlay permission (B+C) — permission regret

---

## 5. North Star Metric

### 5.1 The metric

> **W4ID — the number of users with at least 4 *intentional days* in the trailing 7 days.**
>
> An **intentional day** is a calendar day (device-local) on which the user
> **resolved the loop at least once**: either declared an intent that was later
> marked **Done**, or made an honest **"Just Like That"** admission.
>
> Counted **once per day per user**, whether they did it once or forty times.

Two branches, one definition, because both are the product working: naming a purpose
and completing it (U3/U4), or admitting there is no purpose (U1/U2). What is *not*
an intentional day: a prompt ignored, an intent abandoned, or an unlock that never
got prompted.

### 5.2 The seven criteria

**(a) Direct indicator of user value — mostly yes, with one honest weakness.**
The unit is a person having a day in which they either finished what they came for
or caught themselves. That is U1–U4 restated. **Weakness:** "Done" is self-reported.
There is no permission in the app that could verify it (§1.1), and I am not going to
pretend otherwise. Mitigated by counter-metric C4 (reflexive-Done detection, §7) and
by qualitative interviews — not by a proxy.

**(b) Leading indicator of business value — yes.** Business value is B1 (a decisive
answer) and B3 (segment). W4ID is the *thing being tested*, not a lagging shadow of
it: it moves within days of a product change, and it is the number that would
survive into an eventual monetization conversation, because a person with 4+
intentional days a week is a person getting enough value to pay for or recommend.
D30 retention, by contrast, is lagging by definition.

**(c) Accurately measurable through the product's own instrumentation — computable
today, not readable today. This is the weak leg and I want it stated plainly.**
Every input exists in `intent_log` and `unlock_log` right now: an intentional day is
a `GROUP BY` on `date(completed_at)` filtered to `status='done'` or
`kind='no_intent'`. Any single device can compute W4ID with no new schema. But
Beacon has no telemetry and no network permission, so **the publisher cannot read it
across users** (§1.9, plane C). Reading it requires an explicit decision — an opt-in,
aggregate-only channel (`CLAUDE.md` §11's open item), or a recruited panel that hands
over metadata-only exports. **Do not adopt W4ID and then quietly substitute Play
retention for it.** If neither collection path is chosen, the honest position is that
this product currently cannot measure its own hypothesis at population level, and
that is the first thing to fix.

**(d) Sensitive to product changes within a reasonable timeframe — yes.** A trailing
7-day window with a 4-day threshold responds within one to two weeks to onboarding
changes, prompt-frequency defaults, bubble salience, and (when built) the timer. It
is slow enough not to whipsaw on a single bad day.

**(e) Clear practical meaning — yes.** "Fewer people had 4+ intentional days this
week" decomposes mechanically into: fewer people prompted (survival / skip reasons),
fewer prompted people answering (salience / fatigue), or fewer answers resolving
(bubble not working). Those three are the primary metrics in §6, which is not a
coincidence — they are the NSM's decomposition, not an unrelated shortlist.

**(f) Tied to long-term strategy — yes.** The strategy is the bubble + timer session
loop (`CLAUDE.md` §10). W4ID's *resolution* requirement is exactly the half the
timer is supposed to strengthen; shipping the timer should move this number and
nothing else in the funnel. If the timer ships and W4ID does not move, the wedge
thesis is falsified — which is what B1 asks for.

**(g) Hard to game — largely yes.** Capped once per user per day, so unlock volume
cannot inflate it; it cannot be raised by making the app stickier, by prompting more
often, or by in-app engagement. Two residual holes, both watched in §7: reflexive
Done-tapping inflates it (C4), and it *can* be inflated by prompting a user on a day
they'd otherwise be left alone (C2 caps that).

### 5.3 Rejected NSM candidates

| Candidate | Fails | Why |
|---|---|---|
| Total intents declared / day | (a), (g) | Scales directly with unlock count. Best-case user generates fewer. Rewards the behaviour the product exists to reduce. |
| Weekly active users of the app UI | (a) | Anti-engagement inversion — opening Beacon is overhead, not value. |
| Prompt response **rate** (%) | (e), (g) + no ratio primaries | Denominator is under the product's own control: raise the cooldown, show fewer prompts, rate goes up with zero user benefit. |
| Purposeless-unlock **rate** (`no_intent` share) | (e) | Direction is genuinely ambiguous. Early on, a rise is good (honesty). Later, a fall is good (fewer aimless unlocks). A metric whose good direction changes over the user's life cannot be a north star. Excellent *diagnostic*, kept in §6. |
| Screen time reduced | (c) | Not measurable. Needs `PACKAGE_USAGE_STATS`, which is not declared — and even with it, attribution to Beacon is not achievable in a single-arm rollout. No proxy offered. |
| Average intents per user | (c-ish), + no averages | Mean over a wildly skewed distribution; one heavy user masks fifty silent ones. Absolute counts of users clearing a bar, always. |
| Bubble uptime (minutes live) | (g) | Rises when users *fail* to resolve. Directly rewards the failure state. |
| D30 install retention | (b) | Lagging by a month, and install-level: it cannot distinguish a user getting value from one who forgot to uninstall. Kept as a business/context metric. |
| Play rating / review count | (b), (d) | Lagging, tiny N, dominated by non-behavioural factors. |
| "Beacon Score" (weighted composite of answers, completions, unlock reduction) | composite ban, (e) | When it moves, you cannot say what caused it. Explicitly excluded by the brief and correctly so. |
| Crash-free rate | (a) | A guardrail, not a goal. Perfect stability with zero behaviour change is total failure. |

---

## 6. Primary metrics (4)

All absolute counts of **users** or **installs**, all capped per user per day, all
trailing-7-day windows unless stated. Together they are the NSM's decomposition:
*can it run* → *does it ask* → *do they engage honestly* → *does the loop close*.

**P1 — Surviving installs.**
Count of installs with ≥1 observed unlock on **≥6 of the last 7 days**.
*Why primary:* on the target OEMs this is the precondition for literally everything
else, and a silent failure — an install killed by MIUI produces no crash, no
complaint, and no data. Without P1, every other number is measured on a
survivorship-biased sample. **Watch alongside `noPermission` and `pluginTimeout`
skip counts**, which catch the "installed and running but structurally unable to
prompt" state.

**P2 — Activated installs.**
Count of installs reaching a **first answered prompt within 24h of first launch**.
*Why primary:* the permission cliff is the known top drop-off (`CLAUDE.md` §9), the
onboarding revamp was built to move exactly this, and it is the only stage where a
one-time change can produce a large, fast effect. Ends at *answered*, not at
*permission granted*, so it cannot be gamed by a more aggressive permission ask.

**P3 — Weekly honest-admission users.**
Count of users with **≥1 `no_intent` ("Just Like That") admission** in the last 7 days.
*Why primary:* this is the cleanest evidence that the reflection mechanic fires at
all — a user who admits "no reason" has demonstrably noticed the reflex (U1/U2), and
it is the one signal that cannot be produced by habit or by tapping through. Counted
as users-with-any, not volume, so it does not reward heavier unlocking. A rising
count with flat unlock volume is the strongest early evidence the hypothesis has legs.

**P4 — Weekly loop-closing users.**
Count of users with **≥1 intent marked Done on ≥3 of the last 7 days**.
*Why primary:* the bubble half of the wedge. Distinct from P3 (which is about
noticing) and from the NSM (which is about frequency): P4 asks whether declared
intents actually get resolved rather than left open or swept to `abandoned`. This is
the metric the **timer** should move when it ships — it is the pre-registered
prediction for that feature.

*Deliberately not primary:* unlocks per day (counter, §7), purposeless share
(diagnostic), app opens (excluded), Play retention (business context).

---

## 7. Counter metrics and guardrails

These are two different things and are kept apart on purpose.
**Counter metrics** are monitored: they can move adversely, and that starts a
conversation. **Guardrails** are hard limits: they are never traded for any primary,
and breaching one stops the release.

### 7.1 Counter metrics (monitored — paired to each primary)

| # | Paired with | What breaks if chased single-mindedly | Counter metric |
|---|---|---|---|
| **C1** | P2 (activation) | Onboarding pushes overlay + battery exemption harder and earlier; more people grant, then feel ambushed | Uninstalls within 48h of granting overlay permission; count of installs granting overlay and never answering a prompt |
| **C2** | NSM, P3, P4 | More prompting is the cheapest way to move all three — straight into prompt fatigue and the habituation the 100%-probability default already risks | Prompts shown with no answer (`prompt_shown=1`, no linked intent row) per user per day; users turning prompts **off**; users lowering probability or widening quiet hours after week 1 |
| **C3** | NSM, P4 | Reduction gets sacrificed for engagement: the app succeeds at generating loops while the user unlocks *more* | **Median observed unlocks per user per day must not rise.** If the NSM and unlock volume rise together, treat the NSM as invalid for that period, not as a win |
| **C4** | P4, NSM | "Done" becomes reflexive — users tap check to clear the bubble, not because they finished | Share of Done within **5s** of declaring; collapse in median time-to-Done; intents left `open` >24h |
| **C5** | P1 (survival) | Survival is chased with ever more aggressive foreground/battery behaviour | Play policy warnings; battery-related review mentions; measured battery/day |
| **C6** | P3 | "Just Like That" is made the path of least resistance and becomes a reflex tap rather than an admission | Ratio of `no_intent` to total answers per user trending toward 1.0 alongside falling declared-intent completions |

### 7.2 Guardrails (hard limits — never traded)

1. **No network egress from the app, ever, without explicit opt-in.** Release builds
   must continue to ship with **no `INTERNET` permission**. Any telemetry decision
   that changes this is a product decision (`CLAUDE.md` §11), taken deliberately and
   disclosed — never a side effect of chasing a metric.
2. **Intention text never leaves the device except by explicit user action.** No
   metrics event may carry it, hash it, or embed it. See §8 and §9-Q11 (the current
   CSV export *does* include it — that matters if exports become the panel channel).
3. **No `AccessibilityService`, ever** (`CLAUDE.md` §9/§14). No metric justifies it.
4. **Play vitals:** user-perceived crash rate < 1.09%, ANR rate < 0.47% (Play's bad-
   behaviour thresholds). Breach = fix before any feature work.
5. **Battery < 2%/day** (`CLAUDE.md` §8), on a low-end device, in release.
6. **Unlock → prompt visible ≤ 500ms at p95** (`CLAUDE.md` §8). The prompt is on the
   critical path of the user's own phone; latency here is a tax on every unlock.
7. **User controls are absolute.** Prompts-off means off — no re-prompting to
   reconsider, no decay back to on, one tap to reach, honoured by every code path.
   Quiet hours, cooldown and probability are never overridden for measurement.
8. **No re-engagement notifications.** The one local notification (day-1 recap) is
   opt-in and one-shot. Adding a "you haven't declared an intent today" nudge is
   forbidden regardless of what it would do to the NSM — it converts a wellbeing app
   into an attention product.
9. **Data Safety declaration must match the code exactly**, on every release.
10. **The bubble must not be made more visually prominent by default in a way that
    exposes intention text to onlookers** — the collapsed default state stays the
    default. (Bubble *salience* work should raise noticeability of the bubble, not
    the legibility of the text at arm's length.)

---

## 8. Event schema (metadata only)

Design rules, in priority order:

1. **No free text. Ever.** Intent text stays in `intent_log` for the user's own
   history and never enters the metrics stream. Presets are referenced by `preset_id`
   only, and only for the seeded defaults — user-created preset labels are personal
   text and are recorded as `preset_custom=true` with no id.
2. **No device or app identifiers.** No package names, no advertising id, no
   `ANDROID_ID`. `install_id` is a locally generated random UUID (new on every fresh
   install; see §9-Q9).
3. **Local timestamps stay precise on-device** (the user's own history needs them);
   anything that would ever *leave* the device is bucketed — day for dates, coarse
   buckets for durations.
4. **The exportable unit is a daily rollup, not an event stream.** Even under an
   opt-in channel, what leaves is one small row per device per day.

### 8.1 Events

| Event | Fields | Source today |
|---|---|---|
| `install_first_run` | `install_id`, `first_run_day`, `android_api`, `manufacturer_bucket` | New (prefs has `first_launch_at` only) |
| `onboarding_step` | `step` (enum from `OnboardingStep`), `outcome` (`completed`\|`skipped`\|`exited`) | New |
| `permission_state` | `permission` (`overlay`\|`battery_exemption`\|`notifications`), `granted` (bool), `day` | New |
| `unlock_observed` | `ts`, `prompt_shown` (bool), `skip_reason` (enum) | **Exists** — `unlock_log` |
| `prompt_answered` | `ts`, `outcome` (`intent`\|`no_intent`), `source` (`preset`\|`custom`), `preset_id`\|`preset_custom`, `answer_latency_bucket` | Partly — latency **blocked** (no shown-at timestamp) |
| `intent_resolved` | `client_id`, `resolution` (`done`\|`abandoned`\|`swept`), `duration_bucket` (`<5s`,`<1m`,`<5m`,`<30m`,`<4h`,`≥4h`) | Partly — `done` yes; `abandoned` conflated with `swept` (§9-Q2) |
| `bubble_snoozed` | `client_id`, `ts`, `ended` (`timer`\|`unlock`\|`lost`) | **New** — snooze persists nothing today |
| `setting_changed` | `key` (enum), `bucketed_value` | New |
| `service_lifecycle` | `cause` (`boot`\|`locked_boot`\|`update`\|`engine_start`\|`sweep`), `ts` | Partly — breadcrumbs only, not structured |
| `daily_rollup` | `day`, `unlocks_observed`, `prompts_shown`, `prompts_answered`, `intents_declared`, `done`, `abandoned`, `no_intent`, `intentional_day` (bool), `prompts_enabled` (bool) | New — the only export unit |

### 8.2 Derivation

| Metric | Derived from |
|---|---|
| **NSM (W4ID)** | `daily_rollup.intentional_day` over 7 days |
| P1 surviving installs | `daily_rollup.unlocks_observed > 0` on ≥6 of 7 days |
| P2 activated installs | `install_first_run` → first `prompt_answered` within 24h |
| P3 honest-admission users | `daily_rollup.no_intent > 0` in the window |
| P4 loop-closing users | `daily_rollup.done > 0` on ≥3 days |
| C1 permission regret | `permission_state(overlay, granted)` + Play uninstall data |
| C2 prompt fatigue | `prompts_shown − prompts_answered`; `setting_changed(prompts_enabled=false)` |
| C3 unlock volume | `daily_rollup.unlocks_observed` |
| C4 reflexive Done | `intent_resolved.duration_bucket = '<5s'` share |
| Skip-reason diagnostics | `unlock_observed.skip_reason` |

Nothing above requires storing what the user typed.

---

## 9. Measurable today vs. blocked

### 9.1 Computable today, on a single device, with zero code changes
Observed unlocks per day; prompts shown; full skip-reason distribution; declared
intents by source; `no_intent` admissions; Done vs. abandoned vs. open; time-to-Done
(median, mean, n); preset usage; **ignored prompts** (`prompt_shown=1` with no linked
`intent_log` row — derivable via `unlock_id`); intentional days and therefore the NSM
itself. `IntentStore` already exposes most of these.

### 9.2 Available today with no work, at population level (Play Console)
Installs, uninstalls, D1/D7/D30 install retention, crash-free rate, ANR rate,
excessive-wakeup and battery vitals, ratings and reviews, device/OEM/country mix.
Useful for B4, C1 and C5 — **not** a substitute for anything in §5–§6.

### 9.3 Blocked on instrumentation work (ordered by cost)
1. **Population-level anything.** No telemetry channel exists and the release build
   has no network permission. Requires a product decision: opt-in aggregate rollups,
   or a recruited panel handing over metadata-only exports. **This is the single
   blocker for the entire metric set.**
2. **Daily rollup table** — cheap, local, unblocks NSM/P1/P3/P4 computation and
   makes them stable under retention pruning.
3. **Prompt answer latency** — needs a `prompt_shown_at` timestamp; not recorded.
4. **Snooze events** — in-memory only; nothing persists, so C4/bubble-lifecycle
   analysis has a hole.
5. **True abandonment** — needs to distinguish "user gave up" from "process restarted"
   (§9-Q2).
6. **Onboarding step drop-off** — only the terminal `onboarding_completed` flag exists.
7. **Permission grant/deny timeline** — state is queryable at a point in time, never
   recorded as a transition.
8. **Stable install id / cohorting** — `first_launch_at` lives in prefs and resets
   with app data.
9. **Service-gap detection** — needed before P1 or any unlock count can be trusted
   (§9-Q5).

### 9.4 Not measurable at all with the current permission set — no proxy offered
- **Whether the declared intention was actually performed.** Would need usage access
  at minimum, and even then could not tell "opened the banking app" from "paid the bill".
- **Which app the user opened, or total screen time.** `PACKAGE_USAGE_STATS` is not
  declared, and declaring it is a policy decision with real Play risk.
- **Whether the phone was put down** (as opposed to the bubble being dismissed).
- **Unlocks on a device with no lockscreen** — `ACTION_USER_PRESENT` never fires.
- **Causal attribution of any behaviour change.** Single-arm, no control group, no
  baseline period. Week-4-vs-week-1 comparisons (candidates 36–39) are suggestive
  only; treating them as causal would be the proxy trap wearing a different hat.

---

## 10. Open questions (where the code was ambiguous)

**Q1 — Retention setting is not enforced.** `AppSettings.retentionDays` (90d / 1y /
forever, default 1y) is stored and displayed, but `pruneOlderThan()` is called
**only** from a manual confirm dialog in `lib/your_data_card.dart`. Nothing prunes
automatically. Is the setting a promise (needs a background sweep) or a labelled
manual tool (needs different copy)? This affects longitudinal windows *and* the
privacy claim.

**Q2 — `abandoned` measures process lifecycle, not user behaviour.**
`sweepOpenToAbandoned()` runs at background-engine start. An intent on a phone whose
engine never restarts stays `open` forever; one on an OEM that kills aggressively is
marked `abandoned` even if the user simply hadn't finished. Should abandonment be
time-based (open > N hours) so it means the same thing on every device?

**Q3 — Snooze records nothing.** In-memory `Timer` + `_SnoozeSession`; a process
death loses it silently and leaves the row `open`. Should snooze persist?

**Q4 — `unlock_log` writes can fail silently.** `insertUnlock` runs behind a timeout
wrapper after the prompt decision. A failure undercounts with no marker. Magnitude
unknown — worth measuring before trusting per-day unlock counts.

**Q5 — Unlocks while the service is dead are invisible and unmarked.** The most
consequential gap. Without a service-uptime record, "unlocks observed" silently
under-reports on exactly the devices the product most needs to measure. A
heartbeat, or a boot/restart-derived gap marker, would make P1 real.

**Q6 — `snoozeEnded` is logged as `prompt_shown=0`.** A bubble *was* restored and the
user *was* re-engaged, but the funnel counts it as "not prompted". Intended?

**Q7 — Single-active-intent: `overlayActive` skips.** A second unlock while an intent
is open is logged as skipped. Is that a coverage failure or a success (the bubble was
already doing its job)? Materially changes any prompt-coverage number, and the
`docs/erd/outstanding-intent-prompt-2026-08-15.md` work will change the answer.

**Q8 — `DayOneStats.load` is not day-1 scoped.** It reads a 30-day outcome window and
the last 50 events for "most common reason". Fine for a recap screen; wrong if reused
as a metrics source.

**Q9 — No stable install id.** `first_launch_at` is in prefs, resets with app data,
and `allowBackup=false` means it never migrates. Any cohorting needs an explicit
decision about what an "install" is.

**Q10 — Is self-reported "Done" acceptable as the completion truth?** Nothing in the
app can verify it and no permission would fully close the gap. My position: accept
it, watch C4 hard, and triangulate with interviews — but this should be a conscious
choice, not an unexamined assumption baked into the NSM.

**Q11 — The CSV export includes `intent_text`.** If tester exports become the panel
collection channel, testers will be emailing their raw intentions to a person. That
conflicts with guardrail 7.2-2. A metadata-only export mode should exist *before*
exports are used for measurement.

**Q12 — The timer does not exist.** The wedge is bubble + timer; only the bubble is
built. Any result gathered before the timer ships tests the weaker half of the
hypothesis, so a flat result would not falsify it. Worth deciding whether to
instrument now and measure later, or ship the timer first and instrument once.
