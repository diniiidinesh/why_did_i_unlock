<!--
Beacon store rename — display name + Play listing identity.
Branch: `cursor/beacon-play-listing`. Package / applicationId unchanged.

## Update log

- **2026-07-24:** plan + in-app rename executed (display strings, contact email,
  Kotlin notification title). Privacy / Play listing URLs still placeholders
  until hosting + Console listing exist. See `docs/PLAY_SUBMISSION.md`.
-->

# Beacon store rename (2026-07-24)

## Decisions

| Layer | Value | Rationale |
|---|---|---|
| Play Console **title** (≤30) | `Beacon: Mindful Phone Use` (25 chars) | Distinctive; fits limit; tagline stays in short description |
| On-device **display name** | `Beacon` | Launcher labels truncate long titles; notification chrome stays short |
| Short description | `Your guiding light for mindful phone use. Set intent, stay on track.` | Design brief |
| Contact email | `hi@dineshkaliki.com` | About + privacy + Console |
| Privacy URL | TBD — host via public static site (see §Hosting) | Play requires HTTPS, no login |
| Play listing URL | TBD after first Console app | `…?id=com.whydidiunlock.why_did_i_unlock` |
| Package / `applicationId` | **unchanged** | Permanent after first publish |

## Out of scope

- Renaming Dart package `why_did_i_unlock` or Kotlin package path
- Changing MethodChannel / IsolateNameServer names (`com.whydidiunlock.*`)
- Launcher icon swap (amber mark later; listing asset can update anytime)
- Monetization / analytics

## Touchpoint inventory (code)

Single source: `lib/brand.dart` → imported by UI / export / OEM copy.

| Touchpoint | File | Change |
|---|---|---|
| Brand constants | `lib/brand.dart` | **New** — `appDisplayName`, `playStoreTitle`, `feedbackEmail`, URLs |
| About / Settings links | `lib/about_screen.dart` | Import brand; drop local TODO placeholders for email |
| Home title | `lib/home_screen.dart` | Use `appDisplayName` |
| Overlay `overlayTitle` | `lib/main.dart` (all `showOverlay` sites) | `appDisplayName` |
| CSV share subject | `lib/export_csv.dart` | `'$appDisplayName export'` |
| OEM autostart copy | `lib/oem_autostart_copy.dart` | Substitute display name |
| Android launcher label | `android/.../AndroidManifest.xml` | `android:label="Beacon"` |
| FGS notification title | `UnlockListenerService.kt` | `.setContentTitle("Beacon")` — **approved Kotlin** |
| iOS display name | `ios/Runner/Info.plist` | `CFBundleDisplayName` → Beacon |
| Widget tests | `test/widget_test.dart`, `test/home_screen_test.dart`, `test/about_screen_test.dart` | Assert Beacon / email |

## Docs touchpoints (same change)

| Doc | Update |
|---|---|
| `docs/PLAY_SUBMISSION.md` | Title = Play string; display name = Beacon |
| `docs/PRIVACY_POLICY.md` | Fill app name + email (date at publish) |
| `CLAUDE.md` §12 | Mark store brand **decided: Beacon** |
| `README.md` | Status line: store brand Beacon |
| `docs/erd/beacon-visual-identity-2026-07-24.md` | Append: rename landed; tokens ≠ name was historical |

Do **not** mass-rewrite archive / IntentLock history docs.

## Hosting recommendation

No existing `dineshkaliki.com` site → **yes, a small public repo + GitHub Pages
(+ custom domain)** is the right move:

1. New public repo (e.g. `beacon-site` or `dineshkaliki-com`)
2. Static `privacy/index.html` (source draft: `docs/site/privacy.html` in this app repo)
3. GitHub Pages → custom domain `dineshkaliki.com` (or `www` + apex)
4. Stable URL: `https://dineshkaliki.com/beacon/privacy/`
5. Wire that URL into `lib/brand.dart` `privacyPolicyUrl` — **DONE 2026-07-25**.

Keeping privacy HTML out of the app repo’s private/history concerns is fine;
the draft in `docs/site/` is the copy-paste source of truth until the site repo exists.

## Test plan

### Automated (CI / local)

| ID | Case | Expected |
|---|---|---|
| T-BR-1 | `flutter analyze` | Clean |
| T-BR-2 | `flutter test` | All green; About/Home/widget assert `Beacon` |
| T-BR-3 | About feedback tap | `mailto:hi@dineshkaliki.com` |
| T-BR-4 | Grep `Why Did I Unlock` under `lib/` + `android/app/src/main` | No user-facing leftovers (docs/history OK) |

### Manual on-device (Dinesh)

| ID | Case | Expected |
|---|---|---|
| M-BR-1 | Fresh install release | Launcher label **Beacon** |
| M-BR-2 | Open app → Home | Title **Beacon** |
| M-BR-3 | About | Name Beacon; Send feedback opens mail to hi@… |
| M-BR-4 | Unlock → capture / bubble | Overlay window title Beacon (where the OS shows it) |
| M-BR-5 | Shade / status bar | Ongoing FGS notification title **Beacon** + Beacon silhouette icon (not system lock) |
| M-BR-6 | Status → OEM instructions | Copy refers to Beacon |
| M-BR-7 | CSV export share sheet | Subject mentions Beacon |

## Screenshot note (Play assets)

AI **feature graphics** that say `Intent: Read book for 10m` are fine if
`10m` is read as **user-typed intent text** (not a shipped countdown timer).
Do **not** upload mockups as phone **screenshots** when chrome diverges from
the installed UI (e.g. a bell+badge instead of Done/Snooze). Prefer real
device captures for overlay justification.
