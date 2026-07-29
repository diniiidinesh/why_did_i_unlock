# PLAY_SUBMISSION — Google Play listing & review prep

> Drafts and checklists for getting this app onto Google Play. Covers the two
> declarations most likely to cause a review rejection (special-use foreground
> service, Data Safety) plus the adjacent gates.
>
> **Status: pre-submission.** Nothing here has been submitted or reviewed yet.
> Once a real review happens, record the outcome (accepted as-is / what Google
> pushed back on) in §6 — that's the durable value of this file.
>
> Product/strategy context: `CLAUDE.md` §9 (platform policy risk), §11 (privacy
> stance), §12 (branding). **Store brand decided 2026-07-24: Beacon** (display
> name; package id stays `com.whydidiunlock.why_did_i_unlock`).

---

## 0. Decided listing facts (2026-07-24)

| Field | Value |
|---|---|
| Display / Play title | **Play:** `Beacon: Mindful Phone Use` (25 chars). **On-device:** `Beacon`. See `docs/erd/beacon-store-rename-2026-07-24.md`. |
| Tagline (short description) | "Your guiding light for mindful phone use" (see §3c drafts) |
| Category | **Productivity** (decision rationale in §3c) |
| Ads | No |
| Price | Free (monetization undecided; do not invent a paywall) |
| Distribution | Worldwide |
| Target audience | All ages; not directed at children (IARC will still run) |
| Contact / Console email | `hi@dineshkaliki.com` |
| Privacy host | `https://dineshkaliki.com/beacon/privacy/` (live; see §7) |
| Account type | **Recommend Personal / Individual** for ASAP closed test (see §4) |
| Kotlin notification rename | Approved |

---

## 1. Foreground service: special use justification

### Context Google needs

The app declares **two** foreground services, both `foregroundServiceType="specialUse"`
(`android/app/src/main/AndroidManifest.xml`), each with the required
`PROPERTY_SPECIAL_USE_FGS_SUBTYPE`:

| Service | Subtype property | Owner |
|---|---|---|
| `.UnlockListenerService` | `monitorPhoneUnlocks` | Ours |
| `flutter.overlay.window...OverlayService` | `showOverlayOnUnlock` | `flutter_overlay_window` plugin |

Play Console asks for a justification per app. Cover both; the second is the
weaker case and reviewers may focus there.

### Draft: `UnlockListenerService` (the primary justification)

> Beacon is a digital wellbeing app. Its core function is to ask the user "what
> are you unlocking your phone for?" at the moment they unlock, and then display
> their stated intent as a persistent on-screen reminder until they dismiss it.
>
> To do this, the app must observe the system `ACTION_USER_PRESENT` broadcast,
> which Android delivers only to **runtime-registered** receivers — it cannot be
> registered in the manifest. A runtime-registered receiver requires a live
> application process. The foreground service exists solely to keep that process
> alive so the unlock signal is not missed, and to make its presence visible to
> the user via an ongoing notification.
>
> No standard foreground service type describes this work:
> - `dataSync` / `remoteMessaging`: the app performs **no network activity at
>   all**. It makes zero network requests and has no server component.
> - `mediaPlayback`, `camera`, `microphone`, `mediaProjection`, `phoneCall`,
>   `health`, `connectedDevice`, `location`: none of these capabilities are used,
>   and the corresponding permissions are not requested.
> - `shortService`: time-limited by design, whereas this service must observe
>   unlock events for as long as the user has the feature enabled.
> - `systemExempted`: reserved for system-level use, which this is not.
>
> The service is user-controlled: it is started when the user opens the app and
> grants permission, its behaviour can be turned off in-app at any time via the
> prompt toggle, and it posts a persistent notification for the entire time it is
> running. It collects no data off the device.

### Draft: `OverlayService` (secondary, plugin-owned)

> The second foreground service renders the app's on-screen overlay — the intent
> prompt shown at unlock, and the small draggable reminder that persists
> afterwards. It is declared and managed by the open-source `flutter_overlay_window`
> library the app uses for overlay rendering, and is active only while an overlay
> is actually on screen. Its work is displaying UI the user explicitly asked for
> and can dismiss at any time; no standard foreground service type covers
> "rendering a user-requested overlay."

### 1a. Foreground service TYPE declaration — separate from the above, and needs videos

**Confirmed via web search 2026-07-29** — distinct from the special-use written
justification in §1 (that text goes wherever Console asks for it, likely the same
form). This is Google's newer, structured per-type declaration, required because
`targetSdk=36` (Android 14+) and the app declares FGS types. It appears as a
**prompt in Play Console under Policy → App content** — usually *after* a build
targeting Android 14+ is uploaded, and can take a little time to surface (don't
assume its absence in the first few minutes means it isn't coming).

For **each** declared type (so once for `UnlockListenerService`'s
`monitorPhoneUnlocks`, once for the plugin's `OverlayService`'s
`showOverlayOnUnlock`) Console asks for:
- A description of the functionality using that foreground service type (reuse
  the justification text in §1 above, trimmed to fit).
- **A link to a video demonstrating the feature** — an unlisted YouTube upload is
  the standard route. Record two short screen captures ahead of the Closed
  testing upload, not after: (1) unlocking the phone and the intent-capture
  prompt appearing, (2) declaring an intent and the bubble persisting/dragging.
  Doing this before upload avoids losing days on the 14-day closed-test clock
  scrambling for footage if the prompt blocks the release.
- The specific use case selected from Google's list for that type.

### Draft: `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (Play policy questionnaire)

Paste when Console asks why this permission is declared (manifest comment in
`android/app/src/main/AndroidManifest.xml`; Status screen triggers the system
dialog via `permission_handler`):

> Beacon's core function is to notice phone unlocks and optionally show an intent
> prompt. That requires a long-running process that OEM battery savers (especially
> on Xiaomi, Oppo, Vivo, Realme, and similar) routinely kill. The app declares
> `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` so the user can, from the in-app Status
> screen, open Android's standard one-tap "ignore battery optimizations" dialog
> and allow the unlock-monitoring foreground service to keep running. The request
> is **user-initiated** — never automatic on launch — and can be reversed at any
> time in system settings. The permission is not used for ads, tracking, or any
> background work unrelated to unlock observation and the user-visible overlay.

### Known weaknesses in this justification — prepare for pushback

1. **Two special-use services is more surface than one.** `specialUse` is the
   catch-all type Google scrutinises hardest. Expect the overlay service to draw
   the questions.
2. **We do not control the plugin's service declaration.** If Google demands a
   different `foregroundServiceType` for `OverlayService`, the options are a
   manifest merge override, a plugin fork, or dropping the plugin — all
   expensive. Worth knowing before submitting, not after.
3. **`SYSTEM_ALERT_WINDOW` + foreground service + sideload-style behaviour is a
   known malware pattern.** The justification above is honest and specific, which
   is the best defence, but the store listing must independently make the overlay's
   purpose obvious (see §3 / §3c).

---

## 2. Data Safety form answers

Ground truth as of **v0.6.1+9** (re-verified 2026-07-24 against `pubspec.yaml` +
`android/app/src/main/AndroidManifest.xml`) — **verify again before each
submission**, because a single added dependency can invalidate every answer:

- All user data (declared intent text, timestamps, preferences, presets) is
  written only to on-device storage: `sqflite` (`intents.db`) and
  `shared_preferences`.
- **The app itself initiates zero network calls.** No analytics SDK, no crash
  reporter, no ads, no backend. Main manifest has **no** `INTERNET` permission
  (`INTERNET` appears only under `android/app/src/debug` and `.../profile` for
  Flutter tooling — not in release/main).
- Dependencies added since the 2026-07-17 security review that do **not** change
  the "no collection" answer:
  - `url_launcher` — hands `mailto:` / `https:` URIs to the OS; the app does not
    fetch or upload data.
  - `permission_handler` — opens system permission / battery-optimization UIs;
    no network.
  - `share_plus` — hands a local CSV temp file to the system share sheet; the
    *user* may choose an app that uploads, but Beacon does not transmit.
- `android:allowBackup="false"` — intent history is excluded from Android
  auto-backup, so it does not leave the device that way either.

### Answers

| Question | Answer | Basis |
|---|---|---|
| Does your app collect or share any of the required user data types? | **No** | Play defines "collect" as transmitting off-device. Nothing is transmitted. On-device-only storage is explicitly **not** collection. |
| Is all user data encrypted in transit? | N/A — no data in transit | Follows from the above; the form should skip this once "no collection" is selected. |
| Do you provide a way for users to request data deletion? | N/A — no data leaves the device | Uninstalling / clearing app storage removes the local database. Stated in the privacy policy. |
| Data types (location, personal info, messages, photos, contacts, app activity, etc.) | **None collected** | No contacts, location, usage-stats, or accessibility access. Intent text stays on-device only. |

### Permissions that do NOT require a separate Play declaration form

Confirmed against the current **main** manifest — the app requests
`SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`,
`RECEIVE_BOOT_COMPLETED`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. None of the
first four trigger Play's sensitive-permission declaration forms (Accessibility,
SMS/Call Log, `QUERY_ALL_PACKAGES`, `MANAGE_EXTERNAL_STORAGE`, exact alarms,
etc.). The `<queries>` block is a narrowly scoped `PROCESS_TEXT` intent inserted
by the Flutter engine, **not** `QUERY_ALL_PACKAGES`.

> ⚠️ **`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`** — use the draft in §1 when the
> Policy questionnaire asks for a use-case.

> ⚠️ **This section expires the moment opt-in analytics ships.** Any network
> transmission — even anonymous, even opt-in — flips the first answer to "Yes"
> and requires enumerating data types, retention, and a deletion pathway. The
> Data Safety form must be updated *in the same release*, not after. See the
> analytics entry in `docs/BACKLOG.md`.

---

## 3. Adjacent submission gates

- **[DONE 2026-07-24/25, merged to `main` 2026-07-27] Store brand name.** **Beacon**
  (see §0 / §3c). In-app strings, launcher/splash, and FGS `ic_stat_beacon` shipped.
- **[DONE 2026-07-25] Privacy policy URL.** Hosted at
  `https://dineshkaliki.com/beacon/privacy/` (`beacon-site` + Cloudflare DNS).
  Wired in `lib/brand.dart`.
- **[DONE 2026-07-24] Verify resolved `targetSdk`.** Pinned to 29/36
  (minSdk/targetSdk), see §3b.3.
- **[DONE 2026-07-25] Contact email + Report a problem.** `hi@dineshkaliki.com`
  wired; About → Report a problem mailto + local error buffer
  (`lib/problem_report.dart`).
- **[ ] Store listing must explain the overlay.** Draft copy + screenshot brief
  in §3c. Phone screenshots must be **real device captures** (see §3c — AI
  mockups alone are a policy risk).
- **[DONE 2026-07-29] Exclude tablet/Chromebook/Wear from compatible devices.**
  Manifest now declares `<uses-feature android:name="android.hardware.touchscreen"
  android:required="true"/>` (AndroidManifest.xml) — Beacon's overlay-on-unlock
  mechanic is phone-only. **Still needed at Console time (not a code task):**
  Play Console → Grow → Store presence → Main store listing → (or App content →
  Advanced settings) → **Device catalog** → **Excluded devices** → exclude all
  Tablet devices (and Chromebook/Wear OS if listed). This is what removes the
  mandatory tablet-screenshot requirement from the publish checklist — the
  manifest change alone doesn't retroactively clear an already-surfaced Console
  prompt.
- **[ ] Verify the foreground-service notification is actually visible on
  Android 13+.** `POST_NOTIFICATIONS` is not in the manifest. Play policy expects
  a foreground service to be user-visible; if the ongoing notification is
  suppressed, that is both a policy and a trust problem. **Check on a real
  Android 13+ device** — this is a 30-second observation, and the fix (if needed)
  is a manifest change requiring sign-off per `CLAUDE.md` §7.
- **[ ] `applicationId` is permanent:** `com.whydidiunlock.why_did_i_unlock`.
  It appears in the Play URL forever and cannot be changed after first publish.
  The display name can change freely; this cannot. **Acknowledge before first
  upload** — not a code task.
- **[ ] Fill remaining in-app `TODO_*_UNRESOLVED`** — only `playListingUrl` left
  (§3a); fill after the Play listing exists.

## 3a. In-app placeholder inventory (`TODO_*_UNRESOLVED`)

Grep target: `TODO_.*_UNRESOLVED`. **Do not invent values** — fill when the real
listing URL exists.

| Constant / token | File | Notes |
|---|---|---|
| `feedbackEmail` | `lib/brand.dart` | **DONE:** `hi@dineshkaliki.com`. Re-exported via `lib/about_screen.dart`. |
| `privacyPolicyUrl` | `lib/brand.dart` | **DONE:** `https://dineshkaliki.com/beacon/privacy/` |
| `playListingUrl` = `https://TODO_PLAY_LISTING_URL_UNRESOLVED.placeholder.invalid` | `lib/brand.dart` | **Pending** — fill after the Play listing exists (`…?id=com.whydidiunlock.why_did_i_unlock`). Rate/Share SnackBar “not on Play yet” until then. |

Comment-only mentions (no runtime value): `docs/erd/sprint4-app-shell-plan-2026-07-23.md`.

No `TODO_*_UNRESOLVED` tokens under `android/` as of this inventory.

## 3b. Code / build changes required before submitting

1. **[DONE 2026-07-24] User-declared intent text is logged in release builds.**
   Gated content-bearing logs behind `kDebugMode` (see prior audit notes).
2. **[Build] Play needs an App Bundle, not the split APKs used for sideloading.**
   `flutter build appbundle --release` replaces
   `flutter build apk --release --split-per-abi` for store uploads. The existing
   `upload-keystore.jks` / alias `upload` is the right shape for Play App
   Signing (see `CLAUDE.md` §5).
3. **[DONE 2026-07-24] `minSdk` / `targetSdk` pinned** to 29 / 36.
4. **[Release hygiene] Version for uploads.** Current `pubspec.yaml`:
   `0.6.1+9`. Each Play upload needs a **higher** `+N` versionCode than the
   previous upload.
5. **[DONE 2026-07-25] Display rename → Beacon** + Kotlin notification title +
   About email / privacy URL. **Still pending:** `playListingUrl` (after listing
   exists).

## 3c. Store listing draft (Beacon)

Play field limits (do not exceed):

| Field | Limit | Notes |
|---|---|---|
| App name | **30 characters** | Your draft *"Beacon: Your guiding light for mindful phone use"* is ~52 chars — **too long for the title**. Put the guiding-light line in **short description**. |
| Short description | **80 characters** | Visible above the fold; indexed for search. |
| Full description | 4,000 characters | Explain overlay purpose for reviewers. |

### App name — decided

| Field | Value | Chars |
|---|---|---|
| Play Console title | `Beacon: Mindful Phone Use` | 25 |
| On-device / launcher / notification | `Beacon` | 6 |

Short description still carries the guiding-light line (below).

### Category — Productivity vs Tools

| | Productivity | Tools |
|---|---|---|
| What Play implies | Getting work/life done; habits, focus, planning | Utilities, calculators, device helpers |
| Where this app sits | Intent at unlock → stay on a task → insights | Overlay + foreground service *feel* tool-like |
| Competitor neighbourhood | Digital wellbeing / focus / habit apps | System utilities |

**Pick: Productivity.** The product thesis is behavioural (mindful phone use /
session management), not a system utility. Overlay permission is implementation,
not the category story.

### Short description drafts (≤80)

1. `Your guiding light for mindful phone use. Set intent, stay on track.` (69)
2. `Set your intent at unlock. A floating reminder keeps you on track.` (66)
3. `Ask why you unlocked — then keep that intent visible until you're done.` (70)

**Recommended for closed test:** (1) — matches your design brief.

### Full description draft (paste into Console)

```
Beacon helps you use your phone on purpose.

When you unlock, Beacon can ask: "What are you unlocking for?" Pick a preset
(Check mail, Message someone, Book a cab, and more), type your own intent, or honestly choose
"Just Like That" when there isn't one.

If you set an intent, Beacon shows a small floating reminder that stays on screen
while you use other apps — so your reason for unlocking doesn't disappear the
moment you open Instagram. Drag it, expand it, mark it Done, or snooze it.

Why Beacon needs "Display over other apps"
The floating reminder and the unlock prompt are overlays. That is the product —
not a side feature. Without overlay permission, Beacon cannot show your intent
on top of other apps. You can revoke the permission anytime in system settings.

What stays on your phone
Your intents, history, and settings are stored only on your device. Beacon does
not run ads, does not require an account, and does not send your data to a
server.

You control prompts
Turn prompts on or off, adjust how often they appear, and set quiet hours in
Settings.

Free while we learn
Beacon is free. There are no ads.
```

### Screenshot brief (phone — **real captures required**)

Play requires phone screenshots that **accurately depict the current app**.
Stylized marketing frames are OK only if the **UI inside** matches what users
install. AI mockups that show features you do not ship (session timer, voice mic,
Google "G" chip, Analytics tab, bell badge counts, etc.) are a **deceptive
listing** risk — rejection or takedown, not just bad UX.

**Must (minimum 2; aim for 4+ at ≥1080px portrait):**

1. Unlock capture: "What are you unlocking for?" with real presets + text field.
2. Floating bubble **over another app** (Calendar, Chrome, etc.) — this is the
   overlay justification screenshot reviewers need.
3. Home / insights (Today unlocks + outcomes) — current Stage B UI.
4. Settings or Status (permission / troubleshooting) — optional but helpful.

**Feature graphic (1024×500):** AI banners are fine here — they are marketing art,
not "screenshots of the app." Crop/export to exact size.

**Icon (512×512):** Amber mark OK for closed test; can replace later (listing
asset anytime; launcher icon needs a new build).

### Shot list for Dinesh (when capturing)

1. Fresh unlock → capture screen (release build).
2. Declare "Read book" (or similar) → collapsed / expanded bubble over Calendar.
3. Home with Today / Outcomes visible.
4. Optional: History list; Status with overlay granted.

---

## 4. Closed-testing — Personal account checklist (recommended path)

**Account-type recommendation for ASAP:** sign up as an **Individual / Personal**
developer with `hi@dineshkaliki.com`. You do not have a registered organisation;
creating one needs a legal entity + D-U-N-S and weeks of setup — that fights
"closed test ASAP." Organisation accounts skip the 12-tester / 14-day gate, but
the delay to *become* an org usually costs more than the 14 days.

Applies to **personal accounts created on/after 13 Nov 2023** ([Play Console
Help](https://support.google.com/googleplay/android-developer/answer/14151465)):

### Before signup

- [ ] Decide: **Individual** (recommended) vs Organisation (only if you already
      plan a registered entity + D-U-N-S soon).
- [ ] Confirm `hi@dineshkaliki.com` can receive Google / Play mail.
- [ ] Have payment ready for the one-time Play registration fee.
- [ ] Confirm upload keystore + `key.properties` still in your password manager.

### After signup — create the app

- [ ] Create app → name **Beacon**, free, App (not game).
- [ ] Complete App content: Data Safety (§2), ads = no, content rating (IARC),
      target audience / news / COVID / data-safety questionnaires as shown.
- [ ] Paste FGS special-use + battery-optimization justifications (§1).
- [ ] Upload privacy policy URL (`https://dineshkaliki.com/beacon/privacy/` — live).
- [ ] Store listing: title, short/full description (§3c), feature graphic, icon,
      **real** phone screenshots.
- [ ] Countries: worldwide; pricing: free.

### Closed test track

- [ ] Build: `flutter build appbundle --release` (you run this).
- [ ] Upload AAB to **Closed testing** (not Internal-only — internal does **not**
      satisfy the production-access gate).
- [ ] Add testers by email list or Google Group.
- [ ] Recruit **at least 12**, better **15–20** (buffer for dropouts).
- [ ] Each tester must: open the opt-in link → Become a tester → install from
      Play (not a sideloaded APK).
- [ ] Confirm Console shows ≥12 opted-in before counting days.
- [ ] Keep ≥12 opted-in **continuously for 14 days**. If the count dips below 12,
      the window is at risk — recruit replacements immediately.
- [ ] After 14 continuous days: Dashboard → apply for production access → answer
      Google's testing questionnaire honestly.

### "Continuously opted-in" trap

- Inviting 12 emails is not enough — they must **accept and stay** opted in.
- Opt-out / wrong Google account / never installing can silently break the count.
- Uninstall alone usually does **not** clear opt-in; opt-out does.
- Over-recruit; send a mid-window "please stay opted in" reminder.

### If you later create an Organisation account

Organisation accounts are exempt from the 12/14 rule, but transferring or
recreating apps has its own friction. Prefer Individual now; revisit org only if
you incorporate for other reasons (billing entity, team access, brand legal).

---

## 5. Sideload vs. Play — one hurdle that disappears

The "Restricted Settings" gate documented in `CLAUDE.md` §5 (Android 13+ blocks
the overlay permission on first attempt, requiring **App info → ⋮ → Allow
restricted settings**) applies to **sideloaded** installs. Play-installed apps do
not hit it. Moving to Play removes the single worst step in the current
onboarding funnel — which is an argument for listing sooner rather than later.

---

## 6. Review outcomes

_(Nothing submitted yet. Record each submission's result here — what was accepted
as written, and what Google pushed back on. A rejection reason recorded here is
worth more than everything above it.)_

---

## 7. Privacy policy hosting on `dineshkaliki.com`

**[DONE 2026-07-25]** Live at `https://dineshkaliki.com/beacon/privacy/`
(`beacon-site` + Cloudflare DNS). Wired in `lib/brand.dart`. Incognito-check
before each Console paste if the site ever moves.

### How it was stood up (reference)

1. Public site repo (`beacon-site`) with privacy HTML.
2. DNS for `dineshkaliki.com` → Cloudflare / Pages as configured.
3. Stable URL: `https://dineshkaliki.com/beacon/privacy/`

Markdown source of truth remains `docs/PRIVACY_POLICY.md` (keep in sync with the
hosted HTML when the policy text changes).

---

## 8. Trademark / name collision (Beacon)

**Research snapshot (2026-07-24, not legal advice):**

- Play already has **Beacon: Cyber Safety** (parental cyber-safety education,
  Australia) — different category, different product. Name collision on Play is
  common and usually allowed if you are not impersonating them.
- "Beacon" alone is a **weak / descriptive** word mark in many classes; exclusive
  rights are hard without a distinctive logo + use in commerce.
- No strong evidence of a dominant "Beacon" mindful-unlock competitor on Play.

**Practical recommendation for closed test ASAP:**

1. **Ship as `Beacon`** on Play (title) + amber mark (icon). Differentiate in
   short/full description ("mindful phone use", unlock intent, floating reminder).
2. **Do not wait on a trademark filing** to start closed testing — filing is slow
   and optional at this stage.
3. **Before spending on ads / paid UA**, optionally: quick search on USPTO +
   India IP India for identical marks in software/wellbeing classes; if a
   confusingly similar mark owns the space, consider `Beacon Intent` as a
   fallback title (still ≤30 chars).
4. Logo can change later (listing asset anytime; in-app launcher icon via a new
   AAB). Yes — closed test does not freeze branding forever.

If a rights holder ever objects, the low-cost path is a display-name change on
the same `applicationId` — another reason not to block launch on a perfect name.
