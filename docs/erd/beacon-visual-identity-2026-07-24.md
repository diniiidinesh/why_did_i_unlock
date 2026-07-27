<!--
Beacon visual identity — design tokens + where they apply.
Signed off as a design directive 2026-07-24; implemented on
`cursor/sprint4-stage-b` the same day.

This is the durable token/spec record. Code source of truth:
`lib/beacon_theme.dart`. Bubble chrome: `lib/bubble_widget.dart`.
Bubble hybrid UX (states/actions): `docs/erd/bubble-ux-hybrid-plan-2026-07-24.md`.

## Update log

- **2026-07-24 (ship):** tokens + `beaconDarkTheme()` wired into main UI +
  overlay engines; purple `#6200EE` accents removed from `lib/`.
- **2026-07-24 (doc):** this file archived so the directive survives chat
  summarization; store brand name remains open (`CLAUDE.md` §12) — Beacon
  here is the *visual system*, not a Play Store rename.
-->

# Beacon visual identity

Working UI aesthetic: warmer, calmer “guiding light” — amber accents + frosted
glass — replacing the old Material purple (`#6200EE`) dark theme.

**Not** a resolution of the store-brand / display-name question (`CLAUDE.md` §12).
App label stays “Why Did I Unlock” until that decision lands. Beacon = colors +
chrome language only.

## Tokens (`lib/beacon_theme.dart`)

| Token | Value | Use |
|---|---|---|
| `BeaconColors.amber` | `#FFB300` | Primary accent — switches On, FAB, chart “Done”, selected tabs/chips, prompt preset outlines, bubble stroke |
| `BeaconColors.amberGlow` | `#66FFB300` (~40% amber) | Soft glow / drop-shadow on the floating bubble |
| `BeaconColors.glassFill` | `#99000000` (black @ 60%) | Frosted bubble / glass shell fill |
| `BeaconColors.onGlass` | `#FFFFFFFF` | Text + icons on glass (max contrast) |
| `BeaconColors.onAmber` | `#FF1A1200` | Ink on amber-filled controls (e.g. Done check) |

Theme entry point: `beaconDarkTheme()` — Material 3 dark `ThemeData` seeded with
amber so Switch / FAB / ElevatedButton / progress / checkbox pick up Beacon
without per-widget color hacks.

## Where it is applied

| Surface | Change |
|---|---|
| Main UI (`MyApp`) | `theme: beaconDarkTheme()` |
| Overlay engine (`overlayMain`) | Same theme (capture screen + bubble host) |
| Floating bubble | Glass fill + `BackdropFilter` (σ≈10) + 1.5dp amber stroke + amber glow; white glyphs (`lib/bubble_widget.dart`) |
| Unlock prompt presets | Unselected pill outline → amber |
| Home insight donut | “Done” segment → amber |
| Home window chips | Selected `SegmentedButton` → amber |
| Settings / Manage options | Switches + FAB via theme |
| Dev preview harness | `tool/preview_screens.dart` also uses `beaconDarkTheme()` |

## Intentionally *not* Beacon amber

Permission / status signal colors (green OK, orange warn) on Status/Onboarding
stay semantic — they are not brand accents.

## Related docs

- Bubble interaction / Done / Snooze: `docs/erd/bubble-ux-hybrid-plan-2026-07-24.md` §I.5
- On-device visual QA: `docs/TEST_PLAN.md` cases 61–65
- Backlog marker: `docs/BACKLOG.md` (Beacon DONE entry)
