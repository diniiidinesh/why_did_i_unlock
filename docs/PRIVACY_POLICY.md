# Privacy Policy

**[APP NAME]** — *(store brand undecided; see `CLAUDE.md` §12. Must be filled in
before publishing.)*

**Effective date:** [DATE OF PUBLICATION]

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

The app requests no other permissions.

## Deleting your data

Because nothing is stored anywhere but your phone, you control all of it:

- **Clear the app's storage** (Settings → Apps → [APP NAME] → Storage → Clear
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

Questions about this policy: **[CONTACT EMAIL]**

---

<!--
MAINTENANCE NOTES — not part of the published policy; strip these before hosting.

1. Placeholders to fill: [APP NAME] (x3), [DATE OF PUBLICATION], [CONTACT EMAIL].
   On the contact address: Play requires a working one, and it becomes publicly
   visible. Consider a purpose-made alias rather than a primary personal inbox.

2. Accuracy basis (verify before each release — one added dependency can
   invalidate this whole document):
   - Zero network calls in the dependency tree (security review 2026-07-17,
     CLAUDE.md §5).
   - Local storage only: sqflite `intents.db` + shared_preferences.
   - Manifest permissions are exactly the four listed above.
   - `android:allowBackup="false"` shipped with Sprint 3.

3. This MUST be rewritten if opt-in analytics ships — see the [decision] entry in
   docs/BACKLOG.md and CLAUDE.md §11. The "does not transmit" claims and the
   deletion section both become false. Update this policy and the Play Data
   Safety form in the SAME release, never after.

4. Hosting: Play requires a publicly reachable URL, viewable without login.
   Cheapest durable option is GitHub Pages off this repo. A raw file URL works
   but is fragile — it breaks if the repo is renamed or made private.

5. This is a plain-language draft based on what the code actually does. It has
   not been reviewed by a lawyer. India's DPDP Act 2023 obligations are light for
   an app that processes no personal data off-device, but that is an assumption
   worth confirming if the app ever monetises or collects anything.
-->
