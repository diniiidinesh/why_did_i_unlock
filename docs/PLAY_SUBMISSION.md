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
> stance), §12 (branding — **still open, and blocking the listing**).

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

> Why Did I Unlock is a digital wellbeing app. Its core function is to ask the
> user "what are you unlocking your phone for?" at the moment they unlock, and
> then display their stated intent as a persistent on-screen reminder until they
> dismiss it.
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
   purpose obvious (see §3).

---

## 2. Data Safety form answers

Ground truth as of v0.5.0+7 — **verify against the code before each submission**,
because a single added dependency can invalidate every answer here:

- All user data (declared intent text, timestamps, preferences) is written only
  to on-device storage: `sqflite` (`intents.db`) and `shared_preferences`.
- **Zero network calls anywhere in the dependency tree** (confirmed in the
  2026-07-17 security review, `CLAUDE.md` §5). No analytics SDK, no crash
  reporter, no ads.
- `android:allowBackup="false"` — intent history is excluded from Android
  auto-backup, so it does not leave the device that way either.

### Answers

| Question | Answer | Basis |
|---|---|---|
| Does your app collect or share any of the required user data types? | **No** | Play defines "collect" as transmitting off-device. Nothing is transmitted. On-device-only storage is explicitly **not** collection. |
| Is all user data encrypted in transit? | N/A — no data in transit | Follows from the above; the form should skip this once "no collection" is selected. |
| Do you provide a way for users to request data deletion? | N/A — no data leaves the device | Uninstalling removes the local database. Worth stating plainly in the privacy policy. |
| Data types (location, personal info, messages, photos, contacts, app activity, etc.) | **None collected** | The app requests no permission that would grant access to any of these. It has no contacts, location, usage-stats, or accessibility access. |

### Permissions that do NOT require a separate Play declaration form

Confirmed against the current manifest — the app requests
`SYSTEM_ALERT_WINDOW`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_SPECIAL_USE`,
`RECEIVE_BOOT_COMPLETED`. None of these trigger Play's sensitive-permission
declaration forms (which cover Accessibility, SMS/Call Log, `QUERY_ALL_PACKAGES`,
`MANAGE_EXTERNAL_STORAGE`, exact alarms, etc.). The `<queries>` block is a
narrowly scoped `PROCESS_TEXT` intent inserted by the Flutter engine, **not**
`QUERY_ALL_PACKAGES`, so it needs no declaration.

> ⚠️ **`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` (added Sprint 4, Status screen's
> one-tap battery-exemption dialog) is different — verify before submitting.**
> Unlike the permissions above, Play Console's Policy questionnaire does prompt
> for a declared use-case for this one (it's a commonly-abused permission for
> keeping apps alive against user intent). The justification is the same as
> the foreground-service one in §1: the app's core function requires
> surviving OEM background-kill to observe unlock events, and the request is
> user-initiated (a button on the Status screen), not automatic on launch.
> Confirm the current Play Console form wording before the first submission —
> policy on this permission has shifted before.

> ⚠️ **This section expires the moment opt-in analytics ships.** Any network
> transmission — even anonymous, even opt-in — flips the first answer to "Yes"
> and requires enumerating data types, retention, and a deletion pathway. The
> Data Safety form must be updated *in the same release*, not after. See the
> analytics entry in `docs/BACKLOG.md`.

---

## 3. Adjacent submission gates (not yet done)

- **[ ] Store brand name.** Hard blocker — a listing cannot be created without
  it. Unresolved since May 2026; see `CLAUDE.md` §12.
- **[ ] Privacy policy URL.** Required. No website exists yet. Content is
  genuinely short given "no data leaves the device," but it must be publicly
  hosted at a stable URL.
- **[ ] Verify resolved `targetSdk`.** `android/app/build.gradle.kts` uses
  `flutter.targetSdkVersion` rather than a pinned value, so it moves with the
  Flutter toolchain. Confirm it meets Play's current floor before submitting.
- **[ ] Store listing must explain the overlay.** Screenshots and description
  should make the bubble's purpose self-evident — a reviewer who cannot tell why
  the app needs to draw over other apps will assume the worst.
- **[ ] Verify the foreground-service notification is actually visible on
  Android 13+.** `POST_NOTIFICATIONS` is not in the manifest. Play policy expects
  a foreground service to be user-visible; if the ongoing notification is
  suppressed, that is both a policy and a trust problem. **Check on a real
  Android 13+ device** — this is a 30-second observation, and the fix (if needed)
  is a manifest change requiring sign-off per `CLAUDE.md` §7.
- **[ ] `applicationId` is permanent:** `com.whydidiunlock.why_did_i_unlock`.
  It appears in the Play URL forever and cannot be changed after first publish.
  The display name can change freely; this cannot.

## 3b. Code / build changes required before submitting

Found by auditing the current `main` against Play's requirements. Ordered by how
badly each bites.

1. **[DONE 2026-07-24] User-declared intent text is logged in release builds.**
   `debugPrint` is *not* stripped in Flutter release builds; it reaches Android's
   system log. Roughly six call sites in `lib/main.dart` log the user's actual
   intent text (declare, dismiss, store-confirmation, and three error paths that
   dump the whole event map). Since Android 4.1 other apps can't read those logs
   without a system permission, so this is not an exploitable leak — but it lands
   in bug reports, `adb` captures, and OEM diagnostic uploads, which flatly
   contradicts the privacy policy's "nothing leaves your device." Fix: gate
   content-bearing logs behind `kDebugMode` (keep the structural/lifecycle logs,
   which are what actually aid debugging).
2. **[Build] Play needs an App Bundle, not the split APKs used for sideloading.**
   `flutter build appbundle --release` replaces
   `flutter build apk --release --split-per-abi` for store uploads. The existing
   `upload-keystore.jks` / alias `upload` is exactly the right shape for Play App
   Signing. **Note this improves the risk profile in `CLAUDE.md` §5:** under Play
   App Signing, Google holds the app signing key and a lost *upload* key can be
   reset through support — losing it is no longer unrecoverable the way it is for
   sideloaded builds.
3. **[Gradle — needs sign-off] `minSdk` does not match the documented baseline.**
   `CLAUDE.md` §8 states a baseline of API 29, but
   `android/app/build.gradle.kts` uses `flutter.minSdkVersion`, which resolves to
   Flutter's default (below 29). Sideloading hid this — a store listing will not.
   Shipping to Android versions where the overlay stack has never been tested
   invites crashes and one-star reviews from devices that were never in scope.
   Pin `minSdk = 29` to match the documented intent. Same file: consider pinning
   `targetSdk` explicitly rather than inheriting it, so a Flutter upgrade can't
   silently move it under Play's compliance floor.
4. **[Release hygiene] Bump `pubspec.yaml` version.** Play rejects an upload
   whose version code does not exceed the previous one. Currently `0.5.0+7`.

## 4. Closed-testing requirement

Personal (non-organisation) developer accounts created after Nov 2023 must run a
closed test with a minimum number of testers **continuously opted in for 14
days** before applying for production access.

- **Verify the current tester count in Play Console.** Google has changed this
  number at least once since it launched; do not plan against a remembered value.
- **Organisation accounts are exempt** from the requirement entirely (requires a
  registered entity and a D-U-N-S number). Check which account type applies
  before planning around a constraint that may not apply.
- **"Continuously" is the trap** — testers who opt out break the count.
  Over-recruit.
- The 14 days is a floor; production review afterwards takes additional time.

## 5. Sideload vs. Play — one hurdle that disappears

The "Restricted Settings" gate documented in `CLAUDE.md` §5 (Android 13+ blocks
the overlay permission on first attempt, requiring **App info → ⋮ → Allow
restricted settings**) applies to **sideloaded** installs. Play-installed apps do
not hit it. Moving to Play removes the single worst step in the current
onboarding funnel — which is an argument for listing sooner rather than later.

## 6. Review outcomes

_(Nothing submitted yet. Record each submission's result here — what was accepted
as written, and what Google pushed back on. A rejection reason recorded here is
worth more than everything above it.)_
