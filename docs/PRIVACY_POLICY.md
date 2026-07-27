# Privacy Policy

**Beacon**

**Effective date:** 25 July 2026

---

## The short version

This app does not collect your data. Nothing you type into it, and nothing it
records about your phone use, ever leaves your device.

There are no analytics, no advertising, no crash reporting, no user accounts, and
no servers. The app makes no network requests of any kind.

## What the app stores, and where

Everything below is stored **only in the app's private storage on your phone**:

| What | Why |
|---|---|
| The intent you declare at unlock (a preset you tap, or text you type) | To display it back to you as an on-screen reminder, and to list it in your history |
| Timestamps for when an intent was declared and dismissed | To show your history and to space out how often you are prompted |
| Whether an unlock was declared as having no particular reason | To let you see how often you unlock out of habit |
| Your settings (prompts on/off, and any prompt-frequency preferences) | To remember your choices |

This information is written to a private database inside the app's own storage
area, which other apps on your phone cannot read.

Automatic cloud backup is **disabled** for this app (`allowBackup="false"`), so
your intent history is not copied into Google Drive or device backups.

## What the app does not do

- It does not transmit any information off your device.
- It does not use analytics or advertising services.
- It does not include any third-party tracking SDKs.
- It does not create an account or ask for your identity.
- It does not read your contacts, messages, photos, files, location, browsing
  history, or which apps you use.
- It does not use Android's Accessibility Services or Usage Access.

## Permissions, and why each is needed

- **Display over other apps** (`SYSTEM_ALERT_WINDOW`) — to show the intent
  prompt when you unlock, and the small floating reminder afterwards. This is the
  app's core function.
- **Foreground service** (`FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_SPECIAL_USE`) — Android only notifies an app of unlock
  events while it has a running process, so the app keeps a lightweight
  background service alive to notice when you unlock. While this service is
  running, Android shows an ongoing notification so you always know it is active.
- **Run at startup** (`RECEIVE_BOOT_COMPLETED`) — so the app resumes working
  after you restart your phone, without you having to open it manually.
- **Ignore battery optimizations** (`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`) —
  optional and user-initiated from the Status screen, so aggressive OEM battery
  savers do not silently kill unlock monitoring.

The app requests no other permissions.

## Deleting your data

Because nothing is stored anywhere but your phone, you control all of it:

- **Clear the app's storage** (Settings → Apps → Beacon → Storage → Clear
  data) to erase your intent history immediately.
- **Uninstall the app** to remove all of it permanently.

There is no server-side copy, so there is nothing to request deletion of and no
account to close.

## Children

This app is not directed at children and does not knowingly collect information
from anyone, including children.

## Changes to this policy

If a future version of the app ever collects or transmits any information, this
policy will be updated **before** that version is released, the change will be
described here, and any such collection will be strictly opt-in — off unless you
explicitly turn it on.

## Contact

Questions about this policy: **hi@dineshkaliki.com**

---

<!--
MAINTENANCE NOTES — not part of the published policy; strip these before hosting.

1. No placeholders left. App name + contact filled 2026-07-24; effective date
   filled 2026-07-27 to match the live page. HTML mirror for GitHub Pages:
   `docs/site/privacy.html`.

2. Accuracy basis (verify before each release — one added dependency can
   invalidate this whole document):
   - Zero network calls initiated by the app (see docs/PLAY_SUBMISSION.md §2).
   - Local storage only: sqflite `intents.db` + shared_preferences.
   - `android:allowBackup="false"`.

3. This MUST be rewritten if opt-in analytics ships — see docs/BACKLOG.md and
   CLAUDE.md §11.

4. Hosting: public repo + GitHub Pages + custom domain dineshkaliki.com —
   see docs/erd/beacon-store-rename-2026-07-24.md and PLAY_SUBMISSION.md §7.
-->
