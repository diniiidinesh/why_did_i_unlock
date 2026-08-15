# ERD — Onboarding revamp (copy diet + animated walkthrough + day-1 feature discovery)

> Plan doc. Scoped 2026-08-15, **not yet built**. Owner: Dinesh.
> Parts A/B/C-in-app are pure main-UI-engine work — no isolate, overlay, native,
> or schema changes. The day-1 **notification** (§4D) is the one piece that
> breaks that boundary; it is deliberately isolated into its own PR so the rest
> can ship without it.

## Update log

- **2026-08-15** — Created. Scopes the three onboarding problems raised by
  Dinesh into three separable parts (A/B/C).
- **2026-08-15 (rev 2)** — Reworked against **real closed-test feedback** from 7
  testers (§A1). Part C replaced with Dinesh's day-1 nudge design (§4C).
  Copy targets tightened to a tester's own spec. Added §2.5 (what this work does
  *not* fix — most of the feedback), §4D (notification cost analysis), §10 (full
  copy draft). Decisions recorded: 6 steps OK, "try it now" in, day-1 nudge
  confirmed.
- **2026-08-15 (later)** — Part C reworked again on Dinesh's direction: feature
  discovery is now **anchored tooltips shown from the first unlock**, not
  day-1 cards (§4C). The day-1 notification's job narrows to "come look at your
  stats" (§4D). Nudge thresholds made tunable in one place (§4C.4). Added §11 —
  **handoff guardrails for Cursor**, who will implement this. Copy decisions:
  keep the softer step-1 headline, keep the "No analytics" line for now with an
  explicit coupling note (§10).
- **2026-08-15 (handoff)** — Day-1 notification **decided into scope** (§4D.1–3):
  *local*, not push; `flutter_local_notifications`; triggered off the existing
  unlock event rather than any scheduling API, so no exact-alarm permission and no
  boot rescheduling; must degrade to in-app if the permission is refused. Folded
  into PR 4 with the stats screen. Added §12 — per-PR task briefs for Cursor.
- **2026-08-16** — PR 1 implemented on `cursor/onboarding-copy-diet` (not merged;
  on-device verification still Dinesh's). `OnboardingStep` enum replaces the
  hardcoded `_stepCount = 5` and integer comparisons in
  `didChangeAppLifecycleState` / `_onPageChanged`; page list is derived from
  the enum. §10 copy applied to the existing five steps (How it works prose
  left in place for PR 2). Collapsed "Can't find it?" / "Why does this happen?"
  disclosures added. Still 5 steps — no walkthrough, no "Try it now".

---

## 1. Problem

Three problems, now **confirmed verbatim by testers** rather than inferred:

1. **The first-run screens are too wordy.**
   > "Onboarding is too heavy with text" — Omkar
   > "I found the instructions too verbose and didn't read them at all. Is it
   > possible to do like 3 words per screen — progressive disclosure method — so
   > I can just go next - next - next in 10 secs post install." — Omkar

   Current body copy is ~285 words across five steps, plus the OEM steps list.
   `CLAUDE.md` §9 already flags onboarding as the top drop-off risk; density is
   part of that cliff. **Omkar has given us a usable spec: ~3 words per screen,
   done in ~10 seconds.** §10 targets it.

2. **There is no walkthrough of how the app actually works.** `_HowItWorksStep`
   (`lib/onboarding_screen.dart:314`) is two paragraphs of prose describing a
   *visual, temporal* mechanic. Prose is the wrong medium. Tester evidence that
   the mechanic isn't landing:
   > "I assume clicking on it means I have chosen the reason. However, I also
   > need to click on the tick mark… If I don't, my response isn't recorded" —
   > Vishishta *(this belief is **wrong** — intents are stored at declaration
   > time since T10. The mental model is broken, not the code.)*

3. **Users don't know the prompt-frequency controls exist.**
   > "It does not prompt each time I unlock my phone. Is this by design or am I
   > doing something wrong?" — Omkar
   > "Randomization of prompt was unsatisfactory" — Naveen (uninstalled, day 14)

   **Important caveat — see §2.6.** The "doesn't prompt every time" complaint
   is probably *not* mostly about probability, and onboarding copy alone will
   not fix it.

## 2. Context

### 2.1 What already exists (do not rebuild)

| Asset | Where | Reuse value |
|---|---|---|
| 5-step `PageView`, injectable deps, widget-tested | `lib/onboarding_screen.dart`, `test/onboarding_screen_test.dart` | Structure is sound. Part A is copy-only; Part B replaces one step. |
| `BubbleWidget` — **pure `StatelessWidget`**, no plugin calls | `lib/bubble_widget.dart:90` | **Key finding.** The real bubble (collapsed + expanded, Done/Snooze) renders directly in a walkthrough. No mock, no GIF, no asset — perfect fidelity, cannot drift from the real bubble. |
| Real preset pills + Beacon tokens | `lib/beacon_theme.dart`, capture screen in `lib/main.dart` | Same argument — render real pills, not a picture of pills. |
| Manual prompt trigger, **already excluded from stats** | `_showCaptureScreenManually` (`lib/main.dart`); `BACKLOG.md` | Makes the "try it now" practice prompt (§4E) safe — leaves no `intent_log` row. |
| `oemAutostartNudgeDismissed` pattern | `AppSettings:106` | Exact precedent for every new one-time-flag in §4C. |
| Insight queries (counts, outcome breakdown, durations) | `IntentStore`, `lib/insights/` | The day-1 stats screen (§4C) needs **no new queries**. |
| Background engine wakes on **every unlock** | `lib/main.dart` `backgroundMain` | Removes the need for any alarm/scheduler in §4D. |

### 2.2 New state required in `AppSettings`

All follow the existing `SharedPreferencesAsync` pattern; none touch the DB.

| Key | Type | Purpose |
|---|---|---|
| `first_launch_at` | int (epoch ms) | Anchor for "after the first day". Set once, on first launch. |
| `walkthrough_seen_version` | int (default 0) | Existing-install re-entry (§5.3). |
| `day_one_nudge_shown` | bool | Day-1 stats nudge fires once. |
| `settings_screen_opened` | bool | Retires the Settings tooltip (§4C). |
| `manage_presets_opened` | bool | Retires the Manage-options tooltip (§4C). |
| `settings_tooltip_shows` | int | How many times the Settings tooltip has been shown — capped (§4C.4). |
| `manage_tooltip_shows` | int | Same, for Manage options. |
| `app_launch_count` | int | Incremented once per app launch; drives the fallback banner (§4C.4). |

### 2.5 What this work does **not** fix — read before prioritising

Of ~15 distinct points in the feedback (§A1), **this ERD addresses about four.**
The most severe items are reliability and core-mechanic problems that no amount
of onboarding polish will touch:

| Feedback | Real cause | Where it actually belongs |
|---|---|---|
| "Response isn't recorded… app doesn't work on subsequent unlocks" (Vishishta) | Single-active-intent skip: an undismissed bubble silently suppresses every later prompt (`skip_reason='overlay_active'`) — and/or the stuck-flag P0 | **`docs/erd/outstanding-intent-prompt-2026-08-15.md`** — already scoped, not built |
| "Works only intermittently, but if I open the app it starts asking again" (Vishishta) | Classic OEM background-kill signature — reopening restarts the service | OEM reliability (`BACKLOG.md`); friend soak still open |
| "Opening the app takes 3-4 tries" (Vishishta) | Matches the app-launch stall from the `_overlayIsActive` P0 | Verify against `0.6.3+13`; if it persists, new investigation |
| "Beacon has become easier to ignore… the orange thing is blending in" (Sanchary) | **Direct regression from the 2026-08-11 decision to remove `amberGlow`/`BoxShadow`** (batch 2). The purple bubble was more salient. | Needs a product call — see §A2 |
| "Insights not visible/helpful, pie chart isn't great" (Chukka) | Insight design; wants per-app/category breakdown | Needs `UsageStats` (policy-fragile, `CLAUDE.md` §9) — scope separately |
| "8 options feels like a limitation" (Chukka) | `maxEnabledPresets = 8` | **This is the user-interview answer `CLAUDE.md` was waiting for.** See §A2 |
| "Wanted something that will let you do only that action" (Naveen, uninstalled) | Wants app-blocking / focus-lock — a different product | Strategy, `CLAUDE.md` §12 |
| "Archive the prompt after a few hours if not completed" (Rohit) | Stale outstanding intents | Outstanding-intent ERD |
| "Store manually-typed prompts and reuse them" (Devansh) | Custom intents → saved presets | New backlog item |
| "Not clear what 'Time to mark done' means" (Vishishta) | Home insight label | **Quick win** — rename the label; not onboarding |

**Recommendation:** ship this onboarding work, but do not expect it to move the
feedback needle on its own. The outstanding-intent prompt and the bubble-salience
regression are both higher-leverage than anything in this doc.

### 2.6 "It doesn't prompt every time" — the four real causes

Worth stating precisely, because the obvious copy fix answers the wrong question.
With probability now defaulting to **100%**, a missing prompt is almost never
randomness. The real causes, in likely order:

1. **An outstanding intent** — bubble never dismissed → every later unlock
   skipped. *(Fix: outstanding-intent ERD. Not onboarding.)*
2. **OEM background kill** — service dead until the app is reopened. *(Fix:
   OEM reliability. Onboarding step 4 helps a little.)*
3. **The 1-minute cooldown** — real, deliberate, and the one cause onboarding
   copy *can* honestly set expectations for.
4. **Probability < 100%** — only if the user changed it.

So: onboarding should say "not every single unlock, and you can tune it,"
**not** "we randomise prompts." Overstating randomness would confirm Naveen's
complaint rather than correct it.

## 3. Scope

**In scope:**
- A. Copy diet (§10 has the full draft).
- B. Animated 7-beat walkthrough replacing `_HowItWorksStep`.
- C. Tooltip-based feature discovery from the first unlock, plus the day-1 stats
  screen (§4C).
- D. Day-1 **local** notification (§4D) — **decided: in scope, PR 4, via
  `flutter_local_notifications`.** Does not block Part C.
- E. Optional "try it now" practice prompt (§4E) — **confirmed in**.
- Re-showing the walkthrough to existing installs (§5.3).

**Out of scope (deliberately):**
- Any change to prompt/bubble/triage *behaviour*. Presentation layer only.
- Everything in §2.5.
- Onboarding preset picker (parked 2026-07-25; would re-inflate the flow).
- Localization.

---

## 4. Design

### Part A — Copy diet

**Rules:**
1. **One idea per screen.** Second idea → elsewhere.
2. **Body ≤ 10 words.** (Tightened from 30 after Omkar's spec.) Headline
   carries meaning; body supports.
3. **Justification goes behind a disclosure.** "Android requires this for any
   floating overlay" reassures *us*; the user needs "what do I tap." Collapsed
   "Can't find it?" / "Why?" rows keep it available without taxing everyone.
4. **Never explain behaviour the user hasn't experienced.** This is why
   settings education moved to day 1 (§4C).

Full before/after in **§10**. Net: ~285 words → ~45 words + 7 short captions.

### Part B — The animated walkthrough

**Format:** one full-screen step inside the existing `PageView` — a self-advancing
7-beat sequence in a phone-frame mock, built from **real Flutter widgets**
(§2.1). Not a video, not a GIF.

| # | Beat | What animates | Caption (draft) |
|---|---|---|---|
| 1 | Unlock | Phone frame lights from dark | "You unlock." |
| 2 | Prompt shown | Capture screen slides up, real preset pills | "Beacon asks why." |
| 3 | Prompt selected | One pill highlights and presses | "You pick a reason." |
| 4 | Becomes bubble | Collapses into real `BubbleWidget`, docks to edge | "It becomes a bubble." |
| 5 | Do the work | Mock app content behind; bubble stays on top | "It follows you across apps." |
| 6 | Mark as done | Bubble expands, Done tick pressed, fades | "Tap Done when you're finished." |
| 7 | Snooze | Expanded bubble, Snooze pressed, bubble hides | "Or snooze it for later." |

**Beat 3→4 carries a real teaching load.** Vishishta believed her answer wasn't
recorded until she tapped the tick. The transition must read as *"picking the
reason is what records it; the bubble is the reminder, not the save button."*
Consider a brief "Saved" micro-label on beat 3 — cheap, and it targets a
confirmed misconception.

**Interaction rules:**
- **Auto-advance** ~2.5–3s/beat (named constant; Dinesh feel-tests, §8.4).
- **Tap = pause/resume.** Don't race a reader.
- **Swipe = scrub** between beats.
- **Skip always visible.** Non-negotiable — Omkar wants out in 10 seconds.
- **Plays once, holds on the last beat** with Continue enabled. Never loops
  forever; that reads as stuck.
- **Reduced motion** (`MediaQuery.disableAnimationsOf`): degrade to a static
  scrollable list of the 7 captions. Accessibility + low-end fallback.

**Performance** (`CLAUDE.md` §8): implicit animations only (`AnimatedOpacity`
/`AnimatedPositioned`/`AnimatedContainer`), no `CustomPainter` loop, no `Ticker`
left running after the sequence, no image assets.

### Part C — Tooltip-based feature discovery, from the first unlock *(Dinesh's design — adopted)*

Supersedes the earlier day-1 card design. Two changes on Dinesh's direction:

1. **Tooltips, not cards or banners** — anchored to the actual Settings and
   Manage-options entry points on Home.
2. **From the first unlock, not day 1** — "as soon as the user's attention goes
   towards it, we should let them understand what it is."

The day-1 *notification* survives, but its job narrows to bringing the user back
to look at their stats (§4D).

#### 4C.1 Why tooltips are the right call here

The earlier concern about coach marks was **anchoring fragility and a new
dependency**. The dependency half is solved: Flutter ships the primitive.
`CompositedTransformTarget` + `CompositedTransformFollower` + an `OverlayEntry`
gives a tooltip that tracks a real widget's position, with **zero new packages**
— which keeps `CLAUDE.md` §7's "keep the dependency count low" intact.

Tooltips also beat banners on the specific problem: a banner says "there are
settings somewhere"; a tooltip *points at the thing*, so the user learns the
location and the meaning in one gesture. That directly serves "as soon as their
attention goes toward it."

#### 4C.2 Flow

1. **First app open after the first real unlock** — Home shows the Settings
   tooltip anchored to the Settings row.
2. **Dismiss** ("Got it", tap-outside, or opening the screen) → the Manage-options
   tooltip appears, anchored to its row. **Never both at once** (§4C.3).
3. **A tooltip retires permanently** once its screen has actually been opened
   (`settings_screen_opened` / `manage_presets_opened`).
4. **On first open of each screen**, a dismissible top banner explains what that
   screen controls — the tooltip says *where*, the banner says *what*. One-time
   per screen.
5. **Fallback banner** on Home from launch `nudgeBannerLaunchThreshold` (§4C.4)
   if a screen is still unopened after the tooltips have run out of shows.

**Gate:** never during onboarding, and not on the very first app open if
onboarding just finished in the same session — let the user land on Home once
before anything points at anything.

#### 4C.3 Tooltip guardrails (non-negotiable)

These are the failure modes that make coach marks hated:

- **One tooltip on screen at a time, ever.** Queue them; never race.
- **Never block the underlying control.** The user must be able to tap Settings
  *through* the moment the tooltip is up. A tooltip that intercepts the tap it's
  pointing at is worse than no tooltip.
- **Anchor must be visible.** If the target is scrolled off-screen or not laid
  out, don't show — defer to the next opportunity. Never render a tooltip
  pointing at nothing.
- **Rebuild on rotation / resize**, or dismiss. A stale-positioned tooltip
  floating over unrelated UI is the classic bug here.
- **Always dismissible** by tapping anywhere, not only on a small "Got it".
- **Capped shows** (§4C.4) — a tooltip that reappears forever is nagging, not
  teaching.
- **Must not appear over the capture screen or bubble.** Those are the overlay
  engine, a different engine entirely (`docs/ARCHITECTURE.md` §1) — tooltips are
  main-UI-engine only. Stated explicitly because it would be an easy and very
  bad mistake to make.

#### 4C.4 Tunable thresholds — one place

Dinesh asked for the app-open count to be customisable. All nudge tuning lives in
**one named constant block**, not scattered literals:

```dart
/// All feature-discovery nudge tuning. Kept together deliberately so the
/// cadence can be retuned in one edit after closed-test feedback.
class NudgeTuning {
  static const int maxTooltipShows = 3;              // per tooltip, then retire
  static const int nudgeBannerLaunchThreshold = 5;   // Dinesh's "5th launch or so"
  static const bool fallbackBannerEnabled = true;    // kill switch
}
```

Deliberately **compile-time constants, not user-facing settings**: a threshold
for "how often we nudge you about settings" is not a control a user would ever
sensibly set, and adding it to the Settings screen would add exactly the clutter
this work is trying to remove. If it should become user-facing later, promoting
a constant to an `AppSettings` key is a small, contained change.

#### 4C.5 The day-1 stats screen (still wanted)

Kept, with a narrower purpose: **the destination for the day-1 notification**,
not the vehicle for settings education (the tooltips now own that).

Content is real numbers from existing queries (`IntentStore`, **no new SQL**):
unlocks, intents declared, most common reason, purposeless-unlock count.

**Why it still earns its place:** it answers Chukka's *"unclear what value the
app added"* at the first moment the app actually has data to answer with. That
is a different job from teaching controls, which is why splitting the two is an
improvement rather than a scope cut.

### Part D — The day-1 notification *(needs a decision — real cost)*

**Scope narrowed (Dinesh, 2026-08-15):** now that tooltips own settings discovery
from the first unlock (§4C), the notification's only job is *"come and look at
your first day's stats."* That is a meaningfully smaller promise — and it means
**Part C no longer depends on Part D at all.** If the notification is never
built, feature discovery still works; only the stats re-engagement is lost.

**Blocker confirmed:** `POST_NOTIFICATIONS` is **not** in the manifest
(verified — only `SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE`,
`FOREGROUND_SERVICE_SPECIAL_USE`, `RECEIVE_BOOT_COMPLETED`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), and there is no notification plugin in
`pubspec.yaml`. `CLAUDE.md` §2 already records this. On `targetSdk 36` a
notification needs the permission **and** a runtime request.

**One genuinely nice simplification:** *no scheduler is needed.* The background
engine already wakes on **every unlock**. A day-1 check is just
`if (now - firstLaunchAt > 24h && !dayOneNudgeShown)` evaluated on an unlock we
already handle. No `AlarmManager`, no `WorkManager`, no boot-rescheduling logic.

| Option | What it costs | Notes |
|---|---|---|
| **N-1. In-app only** (no notification) | **Nothing.** No permission, no dependency, no native code | Shows the day-1 screen on the next app open. Only reaches users who open the app — which is the weakness Dinesh is trying to solve |
| **N-2. `flutter_local_notifications`** | New dependency + `POST_NOTIFICATIONS` + runtime request | Well-maintained, standard. Conflicts mildly with "keep the dependency count low" (`CLAUDE.md` §7) |
| **N-3. Post from the existing native FGS path** | **Kotlin change — needs explicit approval** (`CLAUDE.md` §7) + `POST_NOTIFICATIONS` | No new dependency. The service already posts a notification, so the machinery exists |

#### 4D.1 DECIDED (Dinesh, 2026-08-15): build it, via N-2, in PR 4

**"Local notification", not push.** Worth stating explicitly because the words get
used interchangeably: this is an on-device scheduled reminder. A *server* push
(FCM) would require a backend, introduce the first network call anywhere in the
dependency tree, and flip the Play Data Safety form from "no data collected" to a
full disclosure — a `CLAUDE.md` §11 product decision, emphatically not an
onboarding task. **Nothing in this ERD may add a network call.**

**N-2 (`flutter_local_notifications`) over N-3 (native).** N-3 avoids the
dependency but requires a Kotlin change, and this work is being implemented by
Cursor. `CLAUDE.md` §7 protects the native layer precisely because it's delicate
and breaks things that currently work; a new dependency is the cheaper, more
reversible cost. Revisit only if the dependency proves problematic.

#### 4D.2 No scheduling API — piggyback the unlock event

**Do not use `zonedSchedule`.** Exact alarms on Android 13+ drag in
`SCHEDULE_EXACT_ALARM`/`USE_EXACT_ALARM` (a second permission, and one Play
scrutinises), plus boot-rescheduling logic to survive restarts.

Instead: the background engine already wakes on **every unlock**. On that
existing event, check

```
now - firstLaunchAt > 24h && !dayOneNudgeShown && onboardingCompleted
```

and if true, post the notification immediately with a plain `show()`, then set
`dayOneNudgeShown`. No scheduling API, no exact-alarm permission, no boot
rescheduling, no `AlarmManager`.

Trade-off, and it's a favourable one: the reminder fires on the user's next
unlock after the 24h mark rather than at a chosen clock time — i.e. when they are
demonstrably holding the phone, not while it sits on a table.

**Plugin-boundary note:** this runs in the **background** engine, which has
plugins registered normally (it already uses `sqflite` and
`shared_preferences`). Only the **overlay** engine lacks plugins
(`docs/ARCHITECTURE.md` §5). Do not attempt this from overlay-isolate code.

#### 4D.3 The permission ask

`POST_NOTIFICATIONS` goes in the manifest, requested at runtime **at the end of
onboarding**, as a visible opt-in row on the final step — *"Remind me tomorrow to
check my first day"* — defaulted on, one tap to decline. Not a silent system
dialog fired at launch.

**Must degrade gracefully:** if the permission is denied (or the user opts out),
fall back to N-1 behaviour — show the day-1 screen in-app on the next launch past
the 24h mark. **The feature must not depend on the permission being granted.**
This is not optional polish; a notification permission is the single easiest
thing for a user to refuse.

### Part E — "Try it now" practice prompt *(confirmed in)*

Final onboarding step offers a real practice prompt via the existing
`_showCaptureScreenManually` trigger. Safe because manual-trigger answers are
**already** excluded from `intent_log` (`BACKLOG.md`) — a practice run leaves no
trace in history or insights.

- Only offered if the overlay permission was granted; otherwise the step is
  skipped entirely (not shown greyed out).
- Copy must say nothing is saved, or a careful user will worry it polluted their
  data.
- This is the strongest available answer to Vishishta's misconception: she gets
  to see that picking a pill records the intent, before she's relying on it.

---

## 5. Implementation notes

### 5.1 Landmines in the current file — fix, don't work around

- `const int _stepCount = 5;` (`lib/onboarding_screen.dart:69`) — a bare count
  decoupled from the actual `children` list.
- `didChangeAppLifecycleState` and `_onPageChanged` hardcode **step indices 2
  and 3** for permission / battery-exemption refresh
  (`lib/onboarding_screen.dart:116–124`, `168–169`). Insert a step before them
  and permission status **silently** stops refreshing on resume — the user
  grants it, returns, and still sees "Not granted yet."

**Fix:** a named step enum (`_OnboardingStep { valueProp, walkthrough,
permission, oem, yourData, tryIt }`), `_stepCount` derived from it, and matching
on the enum rather than integers.

### 5.2 Step order (6 steps — approved)

1. Value prop (trimmed)
2. **Walkthrough** (Part B) ← replaces `_HowItWorksStep`
3. Permission
4. OEM reliability
5. Your data
6. **Try it now** (Part E) — conditional on permission granted

Note the 6th slot goes to the *experiential* practice prompt, not a
"what you can change" text screen — settings education now lives at day 1 (§4C).
Walkthrough sits at position 2 so the user understands the bubble **before** the
intrusive permission ask that justifies it.

### 5.3 Existing installs — why a second flag is needed

`onboardingCompleted` is already `true` for **every current install**, including
all 29 closed testers — i.e. exactly the people who reported these problems.
Ship behind that flag alone and none of them ever see the new work.

We can't simply reset `onboardingCompleted`: it also gates the permission and
OEM steps, so resetting it would drag existing users back through permission
screens they already completed — and would re-request permissions they've
already granted. That's worse than showing nothing.

**Proposed:** `walkthroughSeenVersion` (int, default 0), tracked *separately*
from onboarding completion.

- Fresh install: onboarding runs, sets `walkthroughSeenVersion = 1` at the end.
- Existing install: `onboardingCompleted == true` but
  `walkthroughSeenVersion == 0` → Home shows a one-time dismissible **"See how
  Beacon works"** card opening the walkthrough standalone. No permission screens,
  no re-onboarding.
- Future: when the mechanic changes (e.g. the timer ships), bump to 2 and the
  same card resurfaces for everyone — without ever touching
  `onboardingCompleted`, which keeps meaning "has completed first run."

Same one-time-card pattern as `oemAutostartNudgeDismissed` (`AppSettings:106`),
which is already proven in production.

### 5.4 Also worth doing while we're here

- A **"How Beacon works"** row in About or Status pointing at the same
  walkthrough widget. Near-zero cost once it exists, and it answers "I forgot
  how snooze works" without a Play listing visit.
- **Rename "Time to mark done"** on Home (Vishishta didn't understand it).
  Trivial copy fix, unrelated to onboarding, but it's a confirmed confusion and
  costs one line.

---

## 6. Testing

**Automated** (`test/onboarding_screen_test.dart` needs substantial rework — it
asserts the current 5-step structure and copy):
- Step enum ↔ page count stay in sync.
- Permission/battery refresh fires on the correct *named* step after reorder.
- Walkthrough: advances all 7 beats; Skip jumps to end; tap pauses; reduced-motion
  renders the static variant.
- `walkthroughSeenVersion` gating: fresh vs. existing install paths.
- Day-1 gating: `firstLaunchAt` + 24h boundary, nudge fires once only.
- Persistent cards clear once `settings_screen_opened` / `manage_presets_opened`
  flip; 5th-launch banner appears only when still unopened.
- "Try it now" step is skipped entirely when permission isn't granted.

**On-device** (Dinesh, per `CLAUDE.md` §7) — new `docs/TEST_PLAN.md` cases:
- Full first run on a **fresh install** (clear data), timed — target ≤ ~15s if
  the walkthrough is skipped.
- Beat timing feels right, no stutter — ideally on a low-end device
  (`BACKLOG.md` "[P2] Untested surfaces" is still open).
- Existing-install path: Home card appears, opens walkthrough, doesn't return
  after dismissal.
- **Permission grant → background → return** after the reorder. *Highest-risk
  regression in this change.*
- Day-1 nudge: needs either a 24h wait or a debug override — **add a hidden
  debug affordance**, otherwise this is untestable in practice.
- "Try it now": confirm the practice prompt leaves **no** row in
  history/insights.

## 7. Risks

1. **Permission-refresh regression from reordering** (§5.1) — highest risk, and
   it fails silently. Mitigated by the enum refactor + a dedicated device case.
2. **The walkthrough becomes the new wall of text.** Enforced by ≤ 8-word
   captions and an always-visible Skip.
3. **Nag fatigue from Part C.** Persistent cards + a launch-count banner can tip
   from helpful to hostile. Every card individually dismissible; banner behind a
   constant.
4. **Scope creep back into length.** Every added screen fights problem 1. Ship
   A + B first.
5. **New permission (`POST_NOTIFICATIONS`) enlarges the permission cliff** we're
   trying to shrink — §4D isolates it into its own decision.
6. **Copy drift from Beacon's voice.** Aggressive trimming risks losing the calm,
   non-preachy tone. Dinesh owns final copy (§10).
7. **Solving the wrong problem.** §2.5 — most tester pain is elsewhere. The risk
   is shipping this, seeing feedback unchanged, and concluding onboarding wasn't
   the issue when it simply wasn't the *biggest* issue.

---

## 8. Decisions (resolved 2026-08-15)

| # | Question | Decision |
|---|---|---|
| 8.1 | Copy draft | **Claude drafts** → §10, Dinesh edits inline |
| 8.2.1 | Part C approach | **Anchored tooltips from the first unlock** (§4C), superseding both C-1/C-2/C-3 and the interim day-1-cards design |
| 8.2.2 | Length ceiling | **6 steps acceptable** |
| 8.2.3 | Existing installs | Explained in §5.3 — separate `walkthroughSeenVersion` flag |
| 8.3 | Tester feedback | **Received** — §A1 |
| 8.5 | "Try it now" | **In** (§4E) |
| — | Nudge thresholds | **Tunable constants in one block** (§4C.4), not user-facing settings |
| — | Step-1 headline | **Keep the original softer headline** (§10) |
| — | "No analytics" copy | **Keep for now**, with an explicit coupling note (§10) |
| — | Day-1 notification | **In scope, PR 4.** Local (not push), via `flutter_local_notifications`, no scheduling API — §4D.1–4D.3 |
| — | Implementation owner | **Cursor** — guardrails in §11, per-PR briefs in §12 |
| — | Priority | Onboarding first, then the §2.5 / backlog items (`docs/BACKLOG.md`) |

**Still open:**
- **§8.4 — beat timing**: 2.5s vs 3s. Named constant; Dinesh feel-tests
  on-device.
- **§A2 — bubble salience**: not this ERD's call, but blocking a real regression.

---

## 9. Sequencing

Four PRs, each independently shippable and verifiable:

1. **PR 1 — Part A copy diet + step-enum refactor** (§5.1, §10). Small,
   low-risk, immediate improvement. Refactor lands here so PR 2 is a clean
   insertion.
2. **PR 2 — Part B walkthrough** + `walkthroughSeenVersion` + Home re-entry card
   (§5.3) + About/Status link (§5.4). The bulk of the work.
3. **PR 3 — Part C tooltips** (§4C) + "Try it now" (§4E) + the "Time to mark
   done" rename (§5.4). Tooltips are the riskiest UI here (anchoring, lifecycle,
   rotation) — keep them isolated from the walkthrough so a problem in one
   doesn't hold back the other.
4. **PR 4 — day-1 stats screen (§4C.5) + the local notification (§4D).**
   Deliberately one PR, not two: the notification's only destination is that
   screen, and the screen alone only reaches users who already open the app.
   Split apart, each half is half a feature. Last in the order, so nothing else
   waits on the new dependency or the permission.

Branches per `CLAUDE.md` §7 — Cursor owns these, so `cursor/…` per the
existing convention: `cursor/onboarding-copy-diet`,
`cursor/onboarding-walkthrough`, `cursor/onboarding-tooltips`,
`cursor/onboarding-day-one`.

---

## 10. Copy draft (Part A) — **for Dinesh to edit inline**

Word counts are body only. Current total ~285 → proposed ~45 + captions.

### Step 1 — Value prop

| | |
|---|---|
| **Now** | *Notice why you picked up your phone* — "Most unlocks happen on autopilot. This app asks what you're unlocking for, then keeps that intent on screen as a bubble until you're done — so a quick check becomes a deliberate one." (33 w) |
| **Proposed** | **Notice why you picked up your phone.**<br>"Most unlocks are autopilot. Beacon makes them deliberate." (8 w) |

> **Decision — keep the original headline** (Dinesh, 2026-08-15). The blunter
> "Most unlocks are autopilot" was the alternative; the softer original is more
> on-brand for a wellbeing app. The autopilot line survives as the body, so the
> hook isn't lost.

### Step 2 — Walkthrough
Replaces the 78-word "How it works" entirely. Captions in §4B (7 × ≤ 6 words).

### Step 3 — Permission

| | |
|---|---|
| **Now** | *One permission is needed* — 72 words + find hint |
| **Proposed** | **One permission.**<br>"The bubble floats over other apps. Android needs your OK." (10 w)<br>Button: `Grant permission`<br>Collapsed: `Can't find it?` → existing `overlayPermissionFindHint` + "You can skip and grant this later in Status & troubleshooting." |

### Step 4 — OEM reliability

| | |
|---|---|
| **Now** | *Some phones need one more step* — 48 words + intro + steps |
| **Proposed** | **Keep Beacon awake.**<br>"Your phone may shut Beacon down in the background." (9 w)<br>Button: `Disable battery optimization`<br>Then matched OEM steps (**keep as-is** — instructions, not prose)<br>Collapsed: `Why does this happen?` → existing `oemGuidanceIntro` |

### Step 5 — Your data

| | |
|---|---|
| **Now** | *Your data stays on your phone* — 52 words |
| **Proposed** | **Stays on your phone.**<br>"No account. No analytics. No internet." (6 w) |

> **Decision — keep "No analytics" for now** (Dinesh, 2026-08-15), despite the
> possibility of opt-in anonymous analytics later (`CLAUDE.md` §11).
>
> Reasoning: the claim is **true today**, and it is one of the app's few genuine
> differentiators — pre-weakening it for a feature that may never ship trades a
> real asset for a hypothetical one. If opt-in analytics does ship, it will be
> **off by default**, so "no analytics" stays true for anyone who doesn't opt in.
>
> **Coupling — do not lose this:** if analytics ships, this line must change in
> the *same release*, exactly as `CLAUDE.md` §11 already requires for the Play
> Data Safety form. Both are the same promise in two places. Whoever implements
> analytics must grep this string.

### Step 6 — Try it now *(new; skipped if permission not granted)*

| | |
|---|---|
| **Proposed** | **Try it once.**<br>"See the prompt and bubble for real. Nothing is saved." (10 w)<br>Buttons: `Show me` · `Skip` |

### Day-1 screen (Part C)

| | |
|---|---|
| **Proposed** | **Your first day with Beacon.**<br>*(stats block — existing queries)*<br>Card 1: **How often Beacon asks** — "Change the gap, quiet hours, and more." → Settings<br>Card 2: **Your reasons** — "Add, reorder, or remove them." → Manage options |

---

## 11. Handoff guardrails — for Cursor

> This ERD is being implemented by **Cursor**, not Claude Code. Everything below
> is the context that is *not* obvious from reading the code, plus the specific
> ways this codebase punishes reasonable-looking changes. Read `CLAUDE.md` §7/§8/§14
> and `docs/ARCHITECTURE.md` §1/§5 before the first edit — they are not optional
> background here.

### 11.1 Hard rules (from `CLAUDE.md` — these override convenience)

- **Never commit directly to `main`.** Branch first (§9 has the names). The app
  is **in Play review**, not yet public (as of 2026-08-16) — but `main` is what
  gets submitted, 29 closed testers already receive builds from it, and public
  release is imminent. Treat it with full production caution.
- **Do not touch Kotlin / native Android files.** Nothing in Parts A/B/C/E needs
  it. If Part D (notification, option N-3) is later approved, that is a *separate*
  decision requiring Dinesh's explicit sign-off — not something to slip in.
- **No new dependencies.** Tooltips use Flutter built-ins (§4C.1). If a package
  feels necessary, stop and ask — that is a signal the design drifted.
- **Do not add analytics or network calls.** Zero network calls exist in the
  entire dependency tree today; that is a deliberate product property, not an
  oversight.
- **Run `flutter analyze` and `flutter test` before declaring anything done.**
  Both must be clean. 239 tests pass today — that is the baseline to preserve.
- **On-device verification is Dinesh's job, not yours.** Write the code and the
  automated tests; hand him the specific cases from §6 to run.

### 11.2 The landmines that will bite

1. **The hardcoded step indices (§5.1).** `didChangeAppLifecycleState` and
   `_onPageChanged` refer to steps **2 and 3 by integer**. Insert the walkthrough
   without the enum refactor and permission-status refresh silently breaks — the
   user grants permission, returns, and still sees "Not granted yet." *Do the enum
   refactor first, in its own PR, before adding any step.*
2. **Three Flutter engines, not one.** Main UI / persistent background / overlay
   (`docs/ARCHITECTURE.md` §1). **All of this work is main-UI-engine only.**
   Tooltips, banners, and the walkthrough must never leak into overlay-engine code
   (`OverlayRoot` / `overlayMain` in `lib/main.dart`).
3. **The overlay engine has no plugins.** Calling `SharedPreferences`, `sqflite`,
   or any plugin from overlay-isolate code throws `MissingPluginException`. If a
   change seems to need it, the design is wrong — the existing
   `IsolateNameServer` port relay is how data crosses that boundary.
4. **Always use `AppSettings`, never `SharedPreferences.getInstance()`.** The
   class exists specifically because `getInstance()` caches a per-isolate
   singleton, which caused a real, shipped bug (stale reads clobbering writes
   across isolates). Every new key in §2.2 goes through `AppSettings` with
   `SharedPreferencesAsync`, matching the existing pattern exactly.
5. **`BubbleWidget` is a pure `StatelessWidget` — keep it that way.** The
   walkthrough reuses it directly (§2.1). Do not add plugin calls, controllers, or
   overlay-specific state to it in order to make the walkthrough easier; that would
   compromise the real bubble to serve a demo.
6. **A clean `flutter test` does not prove on-device correctness.** Desktop test
   backends tolerate things Android rejects (this repo has a documented case where
   a DB pragma passed every test and crashed on a real phone). Treat green tests as
   necessary, not sufficient.

### 11.3 Sync before touching shared docs

Before editing `CLAUDE.md`, `README.md`, `docs/BACKLOG.md`, or
`docs/PLAY_SUBMISSION.md`: `git fetch origin main && git merge origin/main`.
A stale checkout silently *reverts* other sessions' doc fixes with no merge
conflict — this has already happened once (`BACKLOG.md` doc-drift note,
2026-07-29). See `docs/DOC_UPKEEP.md`.

### 11.4 Scope discipline

**Build what §3 lists. Nothing in §2.5.** The temptation will be real: the
feedback in Appendix A is full of good ideas, and several are one-liners. But
the bubble-salience regression, the outstanding-intent prompt, and the insights
rework are each their own piece of work with their own risk profile, and folding
them in here makes this PR unreviewable and unverifiable.

If something in §2.5 looks trivially fixable while you're in the file: **add it
to `docs/BACKLOG.md`, don't fix it.**

The two exceptions already approved (§5.4): the "How Beacon works" re-entry row,
and renaming the "Time to mark done" label. Both are single-line, both are
confirmed confusions.

### 11.5 What "done" means for each PR

1. `flutter analyze` clean.
2. `flutter test` green, with new tests covering the §6 automated list.
3. Branch pushed, PR opened, **not merged** — Dinesh verifies on-device first.
4. `docs/TEST_PLAN.md` updated with the new manual cases (don't mark them passed;
   Dinesh runs them).
5. If behaviour or state changed, append a dated entry to this ERD's Update log
   rather than rewriting the body (`docs/DOC_UPKEEP.md`).

### 11.6 Open questions Cursor should NOT decide alone

- **§4D notification mechanism** (N-1 / N-2 / N-3) — Dinesh's call; N-2 adds a
  dependency and N-3 touches Kotlin.
- **Walkthrough beat timing** — a feel judgement made on-device. Ship it as a
  single named constant and let Dinesh tune it.
- **Any copy change beyond §10.** The copy is the product's voice; §10 is
  Dinesh-approved. Deviating "to fit the layout" is a product change wearing an
  implementation costume — if the copy doesn't fit, raise it.

---

## 12. Per-PR task briefs (Cursor)

> One PR at a time, in order. **Do not start PR N+1 before PR N is verified
> on-device by Dinesh** — PR 1 in particular exists to make PR 2 safe. Read §11
> before the first edit.

### PR 1 — Copy diet + step-enum refactor
**Branch:** `cursor/onboarding-copy-diet`

**Do:**
1. Replace `_stepCount` and the integer step comparisons in
   `lib/onboarding_screen.dart` with an `_OnboardingStep` enum. Derive the count
   from the enum. Match on the enum in `didChangeAppLifecycleState` and
   `_onPageChanged`. **This is the whole point of this PR — do it first.**
2. Apply the §10 copy to all existing steps, verbatim. Do not reword.
3. Add collapsed disclosures ("Can't find it?" on permission, "Why does this
   happen?" on OEM) holding the existing `overlayPermissionFindHint` and
   `oemGuidanceIntro` strings.
4. Update `test/onboarding_screen_test.dart` for the new structure and copy.

**Do NOT:** add or remove steps, touch the walkthrough, touch any other screen.

**Done when:** `flutter analyze` clean, `flutter test` green, tests assert the
enum↔page-count invariant and that permission refresh fires on the *named* step.

---

### PR 2 — Animated walkthrough
**Branch:** `cursor/onboarding-walkthrough`

**Do:**
1. Build the 7-beat walkthrough (§4B) as its own widget, in its own file.
   Reuse `BubbleWidget` and the real preset pills — **do not build mock
   look-alikes, and do not modify `BubbleWidget`** (§11.2 #5).
2. Replace `_HowItWorksStep` with it in the step enum.
3. Beat duration as one named constant (Dinesh tunes it, §8.4).
4. Implement all interaction rules: tap-pause, swipe-scrub, always-visible Skip,
   plays once and holds, reduced-motion static fallback.
5. Add `walkthroughSeenVersion` to `AppSettings`; add the one-time Home re-entry
   card for existing installs (§5.3).
6. Add the "How Beacon works" row in About or Status pointing at the same widget
   (§5.4).

**Do NOT:** use image assets, a `CustomPainter` render loop, or leave a `Ticker`
running after the sequence ends (§4B performance).

**Done when:** analyze/test clean; tests cover all 7 beats advancing, Skip,
pause, reduced-motion variant, and both fresh-vs-existing install paths.

---

### PR 3 — Tooltips + "Try it now" + label rename
**Branch:** `cursor/onboarding-tooltips`

**Do:**
1. Build the anchored-tooltip mechanism using `CompositedTransformTarget` /
   `CompositedTransformFollower` / `OverlayEntry`. **No new package.**
2. Implement every guardrail in §4C.3 — they are requirements, not suggestions.
   The one-at-a-time queue and "never block the underlying control" are the two
   that will otherwise ship as bugs.
3. Add the `NudgeTuning` constant block (§4C.4) and the new `AppSettings` keys
   from §2.2.
4. First-visit banners on Settings and Manage options (§4C.2 step 4).
5. "Try it now" as the final onboarding step (§4E) — skipped entirely, not
   greyed, when overlay permission isn't granted.
6. Rename the "Time to mark done" Home label (§5.4).

**Do NOT:** render tooltips from overlay-engine code, or let a tooltip appear
during onboarding itself.

**Done when:** analyze/test clean; tests cover tooltip retire-on-open, the show
cap, one-at-a-time queueing, and that "Try it now" is skipped without permission.
Dinesh must confirm on-device that a practice prompt leaves **no** row in
history/insights.

---

### PR 4 — Day-1 stats screen + local notification
**Branch:** `cursor/onboarding-day-one`

**Do:**
1. Build the day-1 stats screen (§4C.5) using **existing** `IntentStore`
   queries. Write no new SQL.
2. Add `flutter_local_notifications` and `POST_NOTIFICATIONS`.
3. Trigger from the **background engine's existing unlock handler** per §4D.2 —
   plain `show()`, no `zonedSchedule`, no exact-alarm permission, no boot
   rescheduling.
4. Opt-in row on the final onboarding step, defaulted on (§4D.3).
5. **Graceful degradation:** permission denied or declined → show the day-1
   screen in-app on next launch past 24h. The feature must work without the
   permission.
6. Add a hidden debug affordance to fire the day-1 condition without waiting 24h
   — otherwise this is untestable in practice (§6).

**Do NOT:** add any network call. Do not use FCM or any server push. Do not call
the notification plugin from overlay-isolate code.

**Done when:** analyze/test clean; tests cover the 24h boundary, fires-once, and
the permission-denied fallback path. Update `docs/PLAY_SUBMISSION.md` — a new
permission is a Play-review-relevant change (`docs/DOC_UPKEEP.md` lists this as
that doc's update trigger).

---

## Appendix A — Closed-test feedback (2026-08, 7 testers)

### A1. Verbatim source

Source: `Feedback collected for Beacon.pdf` (Dinesh, 2026-08-15). Testers:
Devansh, Rohit, Omkar, Vishishta, Sanchary, Chukka, Naveen.

**Directly addressed by this ERD:**
- "Onboarding is too heavy with text" (Omkar)
- "Too verbose and didn't read them at all… 3 words per screen… 10 secs" (Omkar)
- "It does not prompt each time I unlock. Is this by design?" (Omkar) — *partly;
  see §2.6*
- "I also need to click on the tick mark… my response isn't recorded"
  (Vishishta) — *mental-model half only; the behavioural half is the
  outstanding-intent gap*
- "Not clear what 'Time to mark done' means" (Vishishta) — §5.4

**Not addressed here — see §2.5:** Vishishta's intermittent prompting and
3-4-tries app launch; Sanchary's bubble salience; Chukka's insights, 8-option
cap, and unclear value; Naveen's uninstall and focus-lock request; Rohit's
archive-after-hours and deviation prompting; Devansh's pastel colours and
save-custom-prompts.

**Already shipped since this feedback:** "Add calling as a default chip" (Rohit)
— "Call someone" was re-added 2026-08-11 (`CLAUDE.md` batch 2).

### A2. Two items that need a product call outside this ERD

1. **Bubble salience regression (Sanchary).**
   > "the beacon has become easier to ignore now… before I would still have the
   > awareness of the purple thing in my peripheral vision. Now the orange thing
   > is almost blending into the… I am just not noticing it."

   This traces directly to the 2026-08-11 decision to clip `_BeaconGlassShell`
   and drop the `amberGlow`/`BoxShadow` token ("crisp rim, no external glow").
   That change fixed a real rendering bug — the glow was drawing as a flat amber
   square — but the fix removed salience along with the artefact. Omkar
   independently asked for the bubble to **move and change colour** to fight
   exactly this habituation. Two testers, same underlying complaint, and it goes
   at the heart of the product thesis (`CLAUDE.md` §10: the bubble *is* the
   differentiator). Worth its own scoped fix — restoring a correctly-clipped
   halo, or periodic subtle motion, is not a copy problem.

2. **`maxEnabledPresets = 8` (Chukka).**
   > "8 options feels like a limitation… it'll be helpful if more options are
   > present"

   `CLAUDE.md` records the cap as staying at 8 "pending a real user-interview
   answer." **This is that answer arriving.** One data point, not a mandate —
   but the question is no longer unanswered, and `docs/USER_INTERVIEWS.md`
   should record it.
