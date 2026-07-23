---
name: T13 Settings Screen
overview: Build a self-contained dark-theme Settings screen + widget tests on `cursor/t13-settings-screen`, wired only to the existing AppSettings API (no HomeScreen/main.dart changes), then one commit and push.
todos:
  - id: checkout-branch
    content: Checkout cursor/t13-settings-screen; leave sprint4-app-shell dirty main.dart/ARCHITECTURE alone
    status: completed
  - id: settings-screen
    content: Add lib/settings_screen.dart (dark theme, chip presets + custom fields with clamp+SnackBar, AppSettings + UrlLauncher inject)
    status: completed
  - id: settings-tests
    content: Add test/settings_screen_test.dart covering preset taps, custom in-range, OOR reject/clamp SnackBar, quiet hours, nav/privacy
    status: completed
  - id: verify-ship
    content: flutter analyze + flutter test green; one commit; push to cursor/t13-settings-screen
    status: completed
isProject: false
---

# T13 Settings Screen

## Preconditions

- Checkout [`cursor/t13-settings-screen`](cursor/t13-settings-screen) (exists; currently same tip as `sprint4-app-shell`). Leave local dirty `lib/main.dart` / `docs/ARCHITECTURE.md` on `sprint4-app-shell` alone (stash or discard before switch — do not carry them onto the T13 branch).
- Hard boundaries: do **not** edit `lib/main.dart`, `lib/intent_store.dart`, `lib/app_settings.dart`, `android/`, or HomeScreen navigation.

## New file: [`lib/settings_screen.dart`](lib/settings_screen.dart)

Self-contained `StatefulWidget` mirroring [`lib/manage_presets_screen.dart`](lib/manage_presets_screen.dart) / [`lib/status_screen.dart`](lib/status_screen.dart) chrome:

- `Scaffold(backgroundColor: Colors.black)`, black `AppBar`, white foreground, `ListView` / `ListTile` rows (`Colors.white` / `white70` / `white10` accents).

**Constructor injection** (defaults = production):

```dart
const SettingsScreen({
  super.key,
  this.settings = const AppSettings(),
  UrlLauncher? launch,
  WidgetBuilder? managePresetsBuilder,
}) : launch = launch ?? _defaultLaunch,
     managePresetsBuilder = managePresetsBuilder; // null → ManagePresetsScreen()
```

- `settings` — same idea as StatusScreen’s `onShowPromptNow` / ManagePresets’ `openStore`.
- `launch` — reuse the [`UrlLauncher`](lib/about_screen.dart) typedef + `_defaultLaunch` pattern; open [`privacyPolicyUrl`](lib/about_screen.dart) (import the existing const — do not duplicate the TODO_ string).
- `managePresetsBuilder` — optional stub for widget tests so tapping “Manage presets” does not drag sqflite into this suite; production path is `Navigator.push` → `const ManagePresetsScreen()`.

**Load on init:** parallel-read `promptsEnabled`, `cooldownMinutes`, `promptProbability`, `quietHoursEnabled`, `quietHoursWindow` into local state; show a centered `CircularProgressIndicator` until ready (same null-vs-empty pattern as ManagePresets).

**Cooldown control decision — fixed chips + Custom, not sliders.** Continuous sliders don't earn their keep here: a random gate at 37% isn't more meaningful than 25/50/75/100, and cooldown is a small discrete set of useful values. Presets also match the product stance that triage *customization* isn't the differentiator (bubble + timer is), while still covering the “type 999 → feedback” test via the Custom field. `AppSettings` still accepts any in-range value; the UI just doesn't expose a continuous dial.

**Rows (only these — no retention / Your data / timer placeholder):**

- **Prompts** — `Switch` → `setPromptsEnabled`
- **Cooldown (minutes)** — `Wrap` of `ChoiceChip`s: **0, 1, 5, 10, 15, 30** + **Custom**. Tapping a preset writes immediately. Custom reveals a compact `TextField` (suffix “min”); submit/unfocus validates then writes.
- **Probability (%)** — chips: **25, 50, 75, 100** + **Custom**. UI shows percent ints; store as `percent / 100.0` via `setPromptProbability`.
- **Quiet hours** — `Switch` + Start / End tiles → `setQuietHoursEnabled` / `setQuietHoursWindow`
- **Manage presets** — chevron `ListTile` → `Navigator.push` → ManagePresets
- **Privacy policy** — `ListTile` → launch `privacyPolicyUrl`; SnackBar on failure like About

**Chip selection state when loading a stored value:** if it matches a preset chip, select that chip; otherwise select **Custom** and prefill the field (so a previously-saved 7 min or 60% still round-trips cleanly).

**Quiet hours time conversion:** `showTimePicker` → `TimeOfDay`; minutes = `hour * 60 + minute` (0–1439). Display as `HH:mm`. Defaults from loaded window (22:00 / 07:00). Wrap-past-midnight is fine — store as-is; policy owns interpretation.

**Custom-field validation (defense in depth):** on submit/unfocus of Custom:

1. Parse int (cooldown minutes) or int-% (probability).
2. If outside `[cooldownMinMinutes, cooldownMaxMinutes]` or percent equivalent of `[probabilityMin, probabilityMax]` (25–100), clamp to the nearest bound, rewrite the field, show a SnackBar (e.g. `Cooldown must be 0–30 minutes` / `Probability must be 25–100%`).
3. Always call `setCooldownMinutes` / `setPromptProbability` with the **clamped** value (never write 999 and “succeed” silently).
4. Invalid/empty parse → SnackBar, leave stored value unchanged (don't wipe to default).

Helper conversions stay private on the State class:

- `_minutesToTimeOfDay` / `_timeOfDayToMinutes`
- `_probabilityToPercent` / `_percentToProbability`

## New file: [`test/settings_screen_test.dart`](test/settings_screen_test.dart)

Setup: `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()` per test (same as [`test/app_settings_test.dart`](test/app_settings_test.dart)). Pump `MaterialApp(home: SettingsScreen(settings: const AppSettings(), launch: …, managePresetsBuilder: …))`, await first load (`pump` + short `pump`/`runAsync` if needed).

Cover:

1. **Prompts switch** round-trips → `AppSettings.promptsEnabled()` flips.
2. **Cooldown preset chip** (e.g. tap `5`) → `cooldownMinutes()` is 5.
3. **Probability preset chip** (e.g. tap `75`) → `promptProbability()` is `0.75`.
4. **Custom cooldown in-range** (e.g. type `7`) → stored 7; Custom chip stays selected on reload.
5. **Custom cooldown OOR** (`999`) → SnackBar; stored clamped to `cooldownMaxMinutes` (30), not 999.
6. **Custom probability OOR** (`10` or `150`) → SnackBar; stored clamped to min/max.
7. **Quiet hours switch** + start/end: at minimum switch round-trip; seed prefs and verify displayed `HH:mm` labels for the window (picker interaction is optional if `showTimePicker` is awkward under `flutter_test`).
8. **Manage presets** tap → pushed route shows stub from `managePresetsBuilder`.
9. **Privacy policy** tap → injected `launch` receives `Uri.parse(privacyPolicyUrl)`.

## Verify / ship

```text
flutter analyze
flutter test
```

One commit on `cursor/t13-settings-screen` only (clear message, e.g. “Add Settings screen with AppSettings-backed prompt triage controls”), then `git push -u origin HEAD`. Do **not** push to `sprint4-app-shell`.

## Report back (post-ship)

- **done/blocked**
- **AppSettings gaps:** none for the requested rows. Present but intentionally unused here: `retentionPeriod` / `setRetentionPeriod`, `onboardingCompleted`, `loadSnapshot`, `cooldownDuration`. Sprint-plan “Your data” / retention / timer-placeholder rows are out of this task’s brief.
