# BACKLOG — Why Did I Unlock

> Deferred engineering/feature work and ideas not yet built. Git-tracked on purpose
> (survives machine switches). Last updated: 2026-07-20.
>
> **Scope:** this file holds *tactical* backlog — features, fixes, polish, ideas.
> For **strategic open decisions** (monetization model, store brand, iOS strategy,
> bubble free-vs-Pro, delay-before-unlock) see **`CLAUDE.md` §11/§12** — the single
> source of truth for those; not duplicated here to avoid drift. For the **next
> sprint's committed scope** (local storage + cooldown) see **`CLAUDE.md` §3**.

Priority tags: **[P1]** = do soon / alongside related work · **[P2]** = worthwhile, not urgent · **[explore]** = needs real scoping before it's buildable · **[decision]** = needs a product call before building.

---

## Reliability / correctness

- **[P1] `android:allowBackup="false"`** — currently unset (defaults to `true`). Harmless today (no stored data), but must be set before/with Sprint 3 storage or Android auto-backup will sweep up intent history, breaking the local-first/privacy stance. Do it alongside the storage work.
- **[P1] OEM autostart onboarding** — aggressive OEMs (Xiaomi/Oppo/Vivo, key India market) block boot auto-restart AND kill the foreground service during normal use unless the user manually grants "Autostart" / disables battery optimization. Not fixable in code — needs a guided in-app screen walking the user through the OEM-specific setting. Fixes both the reboot gap on those OEMs and the general process-kill reliability gap. (Was "Option C" in the reboot discussion.)
- **[P2] `LOCKED_BOOT_COMPLETED` (direct boot)** — the shipped boot fix uses plain `BOOT_COMPLETED`, delivered only *after* the first post-reboot unlock, so that first unlock isn't caught (self-heals from the 2nd). Direct-boot would close it but runs in device-encrypted-only storage before unlock (interacts with Sprint 3 storage encryption), adds complexity, and is expensive to test. Revisit only if reboot-reliability becomes a real complaint.
- **[P2] Graceful degradation when overlay permission is denied/revoked** — currently a silent no-op (confirmed). CLAUDE.md §8 calls for a notification-based fallback instead. Not built.

## Performance (must run on low-end devices — CLAUDE.md §8)

- **[P2] Overlay engine pre-warm** — first capture screen after unlock is slow (cold-starts the overlay's second Flutter engine); the dismiss close+reopen adds a native round-trip. Investigate pre-warming at app start. Ties to the ~500ms unlock-path target.
- **[P2] Untested surfaces** — landscape/rotation (capture screen + pill), low-end-device pass (≤3GB, older Android — only tested on a modern Nothing Phone so far), battery soak vs. the <2%/day target.

## Capture-screen / bubble UX

- **[P2] "OK"/submit button on the capture screen** — currently the custom text field only submits via the keyboard's enter/done key; an on-screen button is more discoverable and reduces confusion. Small, Dart-only quick win.
- **[decision] Skip / "Just Like That" option** — a preset meaning "no real reason, just picked up the phone" that dismisses without forcing a fake intent. Design it as *honest capture that still logs* (valuable data on % purposeless unlocks), NOT a frictionless bypass — a too-easy skip collapses the whole friction mechanic (prompt is already the weakest ingredient per PNAS). Evaluate together with cooldown/triage (Sprint 3). Note tension with the PRD's "Hard Mode" (which *removes* skip).
- **[P2] Drag / edge-snap behavior** — the bubble can be dragged to extreme/partly-offscreen edges. Consider Messenger-style edge-snap (`positionGravity` supports left/right/auto) and/or guaranteeing the × stays reachable.
- **[P2] Adaptive bubble sizing** — width should adapt to intent text up to a max before truncating; consider a smaller-but-legible font. Currently fixed 200×56dp, single line, 14sp, ellipsis.
- **[P2] Smaller footprint + richer actions** — shrink the bubble's on-screen footprint; consider replacing the single × with separate **Done** and **Snooze** actions.
- **[explore] Icon + tap-to-expand hybrid bubble** — each intent gets its own icon; collapsed bubble shows just the icon, tap expands to full text (Messenger chat-head style). Readable pill was chosen for Sprint 2 as simpler; this is a later evaluation. Relates to the Done/Snooze idea.

## Settings / configurability

- **[P2] Configurable durations via a Settings screen** — cooldown duration (Sprint 3 ships it hardcoded at **1 minute**) and, once built, timer duration should become user-configurable via presets + custom (e.g. 5/10/15 min), mirroring the intent-preset UI. Sprint 3 keeps the cooldown a named constant so wiring a future presets UI is small, not a rework.
- **[decision] Bubble customization (color/size/opacity)** — deferred correctly: needs (a) a preferences-persistence layer (likely `shared_preferences`, distinct from the `sqflite` intent log) and (b) monetization clarity, since this was a candidate Pro-gated feature and free-vs-Pro is undecided (CLAUDE.md §11). Don't build gating before the model is chosen.

## Exploratory (bigger bets — need scoping before they enter any sprint)

- **[explore] Suggest which app to open** — from the declared intent, surface/deep-link the relevant app (e.g. a payment intent → payments app).
- **[explore] Detect task completion & nudge** — detect whether the user actually opened the relevant app and whether the task seems done, then nudge. **⚠️ Requires `UsageStatsManager` or `AccessibilityService`** — the exact policy-fragile surface CLAUDE.md §9 flags as the single biggest existential risk (prefer UsageStats over Accessibility). Scope the policy risk first.
- **[explore] Launch app directly from the prompt** — tied to the two above; also overlaps the earlier "open apps from the preset" idea. Note the thesis tension: collapsing declare→act into one tap can undercut the deliberate-friction mechanic. Needs deliberate design, not a quick add.

---

## Also tracked elsewhere (pointers, not duplicated here)

- **Strategic open decisions** (monetization, branding, iOS, bubble free-vs-Pro, delay-before-unlock): `CLAUDE.md` §11/§12.
- **Committed next-sprint scope** (sqflite storage + cooldown design): `CLAUDE.md` §3.
- **Known architectural limitations** (reboot first-unlock gap, OEM kill, 3-engine memory): `docs/ARCHITECTURE.md` §6.
