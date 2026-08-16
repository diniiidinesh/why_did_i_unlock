import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// Typed, isolate-safe access to every user-configurable setting.
///
/// Every read/write goes through a **freshly constructed** [SharedPreferencesAsync]
/// — never `SharedPreferences.getInstance()` and never a cached instance field.
/// `getInstance()` caches a static per-isolate singleton on first use, which is a
/// real, previously-hit bug here: settings are written from the main UI engine
/// (Settings screen) and read from the separate persistent background engine's
/// isolate (see the doc comment on `_shouldPrompt()` in `lib/main.dart`, and
/// `docs/DATA_MODEL.md`). `SharedPreferencesAsync` reads the platform directly on
/// every call, so a write in one isolate is visible to the next read in another —
/// which is the entire reason this class exists rather than every screen touching
/// `shared_preferences` ad hoc.
///
/// Clamping is enforced **here**, not just in the Settings UI (T13). Cooldown and
/// probability are the product's active ingredient, not ordinary preferences — a
/// user who sets 4 hours / 10% has silently disabled the app and will report it as
/// broken (`docs/DATA_MODEL.md` §5). Enforcing the bound at the storage layer means
/// no future call site — including code that hasn't been written yet — can bypass
/// it by mistake.
class AppSettings {
  const AppSettings();

  // ---------------------------------------------------------------------
  // Keys. `_promptsEnabledKey`'s STRING VALUE must stay 'prompts_enabled' —
  // it matches the pre-existing key `lib/main.dart` has stored under since
  // v0.4.0, so upgrading users keep their existing on/off choice rather than
  // silently reverting to the default.
  // ---------------------------------------------------------------------
  static const String _promptsEnabledKey = 'prompts_enabled';
  static const String _cooldownMinutesKey = 'cooldown_minutes';
  static const String _promptProbabilityKey = 'prompt_probability';
  static const String _quietHoursEnabledKey = 'quiet_hours_enabled';
  static const String _quietHoursStartMinutesKey = 'quiet_hours_start_minutes';
  static const String _quietHoursEndMinutesKey = 'quiet_hours_end_minutes';
  static const String _retentionDaysKey = 'retention_days';

  /// Key used by the storage key literal below: `'onboarding_completed'` was
  /// the name already specified in the signed-off Sprint 4 plan
  /// (`docs/erd/sprint4-app-shell-plan-2026-07-23.md` §5), so this matches
  /// rather than inventing a new name.
  static const String _onboardingCompletedKey = 'onboarding_completed';
  static const String _oemAutostartNudgeDismissedKey = 'oem_autostart_nudge_dismissed';
  static const String _walkthroughSeenVersionKey = 'walkthrough_seen_version';
  static const String _firstLaunchAtKey = 'first_launch_at';
  static const String _dayOneNudgeShownKey = 'day_one_nudge_shown';
  static const String _dayOneReminderEnabledKey = 'day_one_reminder_enabled';
  static const String _dayOneNotificationPostedKey = 'day_one_notification_posted';
  static const String _settingsScreenOpenedKey = 'settings_screen_opened';
  static const String _managePresetsOpenedKey = 'manage_presets_opened';
  static const String _settingsTooltipShowsKey = 'settings_tooltip_shows';
  static const String _manageTooltipShowsKey = 'manage_tooltip_shows';
  static const String _appLaunchCountKey = 'app_launch_count';

  // ---------------------------------------------------------------------
  // Bounds — see docs/DATA_MODEL.md §5 (Settings) for the product rationale.
  // ---------------------------------------------------------------------
  static const int cooldownMinMinutes = 0;
  static const int cooldownMaxMinutes = 30;
  static const double probabilityMin = 0.25;
  static const double probabilityMax = 1.0;

  /// Matches the values already hardcoded in `lib/main.dart` (`intentCooldown`,
  /// `promptProbability`) so behaviour is unchanged for anyone who never opens
  /// Settings.
  static const int defaultCooldownMinutes = 1;
  /// 100% — ask on every unlock once cooldown clears. The old 50% default
  /// felt broken ("sometimes nothing happens") more often than it helped
  /// resist habituation; power users can still dial probability down in
  /// Settings.
  static const double defaultProbability = 1.0;
  static const bool defaultPromptsEnabled = true;
  static const bool defaultQuietHoursEnabled = false;
  static const int defaultQuietHoursStartMinutes = 22 * 60; // 22:00
  static const int defaultQuietHoursEndMinutes = 7 * 60; // 07:00 — wraps past midnight
  static const RetentionPeriod defaultRetention = RetentionPeriod.oneYear;
  static const bool defaultOnboardingCompleted = false;
  /// Opt-in on the last onboarding step — defaulted on (§4D.3).
  static const bool defaultDayOneReminderEnabled = true;

  /// Bump when the mechanic itself changes (e.g. the timer ships) so the
  /// Home re-entry card resurfaces. Independent of [onboardingCompleted] —
  /// see `docs/erd/onboarding-revamp-2026-08-15.md` §5.3.
  static const int currentWalkthroughVersion = 1;
  static const int defaultWalkthroughSeenVersion = 0;

  // ---------------------------------------------------------------------
  // Prompts on/off
  // ---------------------------------------------------------------------
  Future<bool> promptsEnabled() async {
    final prefs = SharedPreferencesAsync();
    return await prefs.getBool(_promptsEnabledKey) ?? defaultPromptsEnabled;
  }

  Future<void> setPromptsEnabled(bool value) async {
    await SharedPreferencesAsync().setBool(_promptsEnabledKey, value);
  }

  // ---------------------------------------------------------------------
  // Onboarding completion — gates whether the 5-step flow (T4) is shown on
  // launch. Default false (never completed), so a fresh install shows
  // onboarding; the flow itself calls setOnboardingCompleted(true) on its
  // last step. Deliberately its own flag rather than inferred from some
  // other state (e.g. "has the overlay permission"), since a user could
  // grant/revoke that permission independently of ever having seen the
  // explanatory screens.
  // ---------------------------------------------------------------------
  Future<bool> onboardingCompleted() async {
    final prefs = SharedPreferencesAsync();
    return await prefs.getBool(_onboardingCompletedKey) ?? defaultOnboardingCompleted;
  }

  Future<void> setOnboardingCompleted(bool value) async {
    await SharedPreferencesAsync().setBool(_onboardingCompletedKey, value);
  }

  /// How many times the user has seen the current walkthrough mechanic.
  /// `0` = never (existing installs, or a fresh install mid-onboarding).
  Future<int> walkthroughSeenVersion() async {
    final prefs = SharedPreferencesAsync();
    return await prefs.getInt(_walkthroughSeenVersionKey) ?? defaultWalkthroughSeenVersion;
  }

  Future<void> setWalkthroughSeenVersion(int value) async {
    await SharedPreferencesAsync().setInt(_walkthroughSeenVersionKey, value);
  }

  // ---------------------------------------------------------------------
  // Feature discovery (§4C) — Home tooltips + first-visit banners.
  // firstLaunchAt / dayOneNudgeShown were written in PR 3 so PR 4 can
  // consume them without a second prefs migration. Reminder-opt-in and
  // "notification already posted" are PR 4's own keys.
  // ---------------------------------------------------------------------
  Future<int?> firstLaunchAtMs() async {
    return SharedPreferencesAsync().getInt(_firstLaunchAtKey);
  }

  /// Sets once; later calls are no-ops.
  Future<void> ensureFirstLaunchAt(DateTime now) async {
    final prefs = SharedPreferencesAsync();
    if (await prefs.getInt(_firstLaunchAtKey) != null) return;
    await prefs.setInt(_firstLaunchAtKey, now.millisecondsSinceEpoch);
  }

  /// Overwrites [firstLaunchAt] — used only by About's hidden long-press
  /// so Dinesh can fire the recap without waiting 24h (`§6`).
  Future<void> overwriteFirstLaunchAt(DateTime at) async {
    await SharedPreferencesAsync().setInt(_firstLaunchAtKey, at.millisecondsSinceEpoch);
  }

  Future<bool> dayOneNudgeShown() async {
    return await SharedPreferencesAsync().getBool(_dayOneNudgeShownKey) ?? false;
  }

  Future<void> setDayOneNudgeShown(bool value) async {
    await SharedPreferencesAsync().setBool(_dayOneNudgeShownKey, value);
  }

  Future<bool> dayOneReminderEnabled() async {
    return await SharedPreferencesAsync().getBool(_dayOneReminderEnabledKey) ??
        defaultDayOneReminderEnabled;
  }

  Future<void> setDayOneReminderEnabled(bool value) async {
    await SharedPreferencesAsync().setBool(_dayOneReminderEnabledKey, value);
  }

  Future<bool> dayOneNotificationPosted() async {
    return await SharedPreferencesAsync().getBool(_dayOneNotificationPostedKey) ?? false;
  }

  Future<void> setDayOneNotificationPosted(bool value) async {
    await SharedPreferencesAsync().setBool(_dayOneNotificationPostedKey, value);
  }

  Future<bool> settingsScreenOpened() async {
    return await SharedPreferencesAsync().getBool(_settingsScreenOpenedKey) ?? false;
  }

  Future<void> setSettingsScreenOpened(bool value) async {
    await SharedPreferencesAsync().setBool(_settingsScreenOpenedKey, value);
  }

  Future<bool> managePresetsOpened() async {
    return await SharedPreferencesAsync().getBool(_managePresetsOpenedKey) ?? false;
  }

  Future<void> setManagePresetsOpened(bool value) async {
    await SharedPreferencesAsync().setBool(_managePresetsOpenedKey, value);
  }

  Future<int> settingsTooltipShows() async {
    return await SharedPreferencesAsync().getInt(_settingsTooltipShowsKey) ?? 0;
  }

  Future<void> setSettingsTooltipShows(int value) async {
    await SharedPreferencesAsync().setInt(_settingsTooltipShowsKey, value);
  }

  Future<int> manageTooltipShows() async {
    return await SharedPreferencesAsync().getInt(_manageTooltipShowsKey) ?? 0;
  }

  Future<void> setManageTooltipShows(int value) async {
    await SharedPreferencesAsync().setInt(_manageTooltipShowsKey, value);
  }

  Future<int> appLaunchCount() async {
    return await SharedPreferencesAsync().getInt(_appLaunchCountKey) ?? 0;
  }

  Future<void> incrementAppLaunchCount() async {
    final next = await appLaunchCount() + 1;
    await SharedPreferencesAsync().setInt(_appLaunchCountKey, next);
  }

  // ---------------------------------------------------------------------
  // Home "Battery & autostart" nudge — dismissed once so it isn't naggy.
  // Default false (show nudge when battery exemption is missing).
  // ---------------------------------------------------------------------
  Future<bool> oemAutostartNudgeDismissed() async {
    final prefs = SharedPreferencesAsync();
    return await prefs.getBool(_oemAutostartNudgeDismissedKey) ?? false;
  }

  Future<void> setOemAutostartNudgeDismissed(bool value) async {
    await SharedPreferencesAsync().setBool(_oemAutostartNudgeDismissedKey, value);
  }

  // ---------------------------------------------------------------------
  // Cooldown
  // ---------------------------------------------------------------------
  Future<int> cooldownMinutes() async {
    final prefs = SharedPreferencesAsync();
    final stored = await prefs.getInt(_cooldownMinutesKey);
    if (stored == null) return defaultCooldownMinutes;
    return stored.clamp(cooldownMinMinutes, cooldownMaxMinutes);
  }

  Future<Duration> cooldownDuration() async => Duration(minutes: await cooldownMinutes());

  /// Clamps silently rather than throwing — the Settings UI (T13) is expected
  /// to constrain its slider to the same bounds, so this is defence in depth,
  /// not the primary guard, and a silent clamp degrades gracefully if that UI
  /// constraint is ever loosened by mistake.
  Future<void> setCooldownMinutes(int minutes) async {
    final clamped = minutes.clamp(cooldownMinMinutes, cooldownMaxMinutes);
    await SharedPreferencesAsync().setInt(_cooldownMinutesKey, clamped);
  }

  // ---------------------------------------------------------------------
  // Probability
  // ---------------------------------------------------------------------
  Future<double> promptProbability() async {
    final prefs = SharedPreferencesAsync();
    final stored = await prefs.getDouble(_promptProbabilityKey);
    if (stored == null) return defaultProbability;
    return stored.clamp(probabilityMin, probabilityMax);
  }

  Future<void> setPromptProbability(double probability) async {
    final clamped = probability.clamp(probabilityMin, probabilityMax);
    await SharedPreferencesAsync().setDouble(_promptProbabilityKey, clamped);
  }

  // ---------------------------------------------------------------------
  // Quiet hours — a window during which prompts are suppressed entirely,
  // independent of cooldown/probability. See docs/DATA_MODEL.md §11.
  //
  // Stored as minutes-since-local-midnight (0..1439) rather than a formatted
  // time string, so comparisons in the policy that consumes this (T9's
  // QuietHoursPolicy) are plain integer arithmetic. The window MAY wrap past
  // midnight (e.g. start=22:00, end=07:00) — that wraparound is the
  // consuming policy's responsibility to interpret correctly, not this
  // storage layer's; see the warning in docs/DATA_MODEL.md §11 about the
  // naive-range-check trap.
  // ---------------------------------------------------------------------
  Future<bool> quietHoursEnabled() async {
    final prefs = SharedPreferencesAsync();
    return await prefs.getBool(_quietHoursEnabledKey) ?? defaultQuietHoursEnabled;
  }

  Future<void> setQuietHoursEnabled(bool value) async {
    await SharedPreferencesAsync().setBool(_quietHoursEnabledKey, value);
  }

  Future<QuietHoursWindow> quietHoursWindow() async {
    final prefs = SharedPreferencesAsync();
    final start = await prefs.getInt(_quietHoursStartMinutesKey) ?? defaultQuietHoursStartMinutes;
    final end = await prefs.getInt(_quietHoursEndMinutesKey) ?? defaultQuietHoursEndMinutes;
    return QuietHoursWindow(
      startMinutes: _clampMinuteOfDay(start),
      endMinutes: _clampMinuteOfDay(end),
    );
  }

  Future<void> setQuietHoursWindow(QuietHoursWindow window) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setInt(_quietHoursStartMinutesKey, _clampMinuteOfDay(window.startMinutes));
    await prefs.setInt(_quietHoursEndMinutesKey, _clampMinuteOfDay(window.endMinutes));
  }

  static int _clampMinuteOfDay(int minutes) => minutes.clamp(0, 24 * 60 - 1);

  // ---------------------------------------------------------------------
  // Retention
  // ---------------------------------------------------------------------
  Future<RetentionPeriod> retentionPeriod() async {
    final prefs = SharedPreferencesAsync();
    final stored = await prefs.getInt(_retentionDaysKey);
    if (stored == null) return defaultRetention;
    return RetentionPeriod.fromStoredDays(stored);
  }

  Future<void> setRetentionPeriod(RetentionPeriod period) async {
    await SharedPreferencesAsync().setInt(_retentionDaysKey, period.storedDays);
  }

  // ---------------------------------------------------------------------
  // Snapshot — a single fetch of everything the unlock-time triage check
  // (T9) and the overlay config relay (T11) need, so neither has to make six
  // separate SharedPreferencesAsync round-trips per unlock. Retention is
  // deliberately excluded: it's read by app-foreground pruning (Stage B),
  // never by the unlock hot path, so bundling it here would be scope the
  // hot-path callers don't need.
  // ---------------------------------------------------------------------
  Future<AppSettingsSnapshot> loadSnapshot() async {
    final prefs = SharedPreferencesAsync();
    final results = await (
      prefs.getBool(_promptsEnabledKey),
      prefs.getInt(_cooldownMinutesKey),
      prefs.getDouble(_promptProbabilityKey),
      prefs.getBool(_quietHoursEnabledKey),
      prefs.getInt(_quietHoursStartMinutesKey),
      prefs.getInt(_quietHoursEndMinutesKey),
    ).wait;

    final promptsEnabled = results.$1 ?? defaultPromptsEnabled;
    final cooldownMinutes = (results.$2 ?? defaultCooldownMinutes).clamp(cooldownMinMinutes, cooldownMaxMinutes);
    final probability = (results.$3 ?? defaultProbability).clamp(probabilityMin, probabilityMax);
    final quietHoursEnabled = results.$4 ?? defaultQuietHoursEnabled;
    final quietStart = _clampMinuteOfDay(results.$5 ?? defaultQuietHoursStartMinutes);
    final quietEnd = _clampMinuteOfDay(results.$6 ?? defaultQuietHoursEndMinutes);

    return AppSettingsSnapshot(
      promptsEnabled: promptsEnabled,
      cooldown: Duration(minutes: cooldownMinutes),
      probability: probability,
      quietHoursEnabled: quietHoursEnabled,
      quietHoursWindow: QuietHoursWindow(startMinutes: quietStart, endMinutes: quietEnd),
    );
  }
}

/// A quiet-hours window in minutes-since-local-midnight. May wrap past
/// midnight (`startMinutes > endMinutes`) — interpreting that correctly is
/// the consumer's job (`QuietHoursPolicy`, added in T9), not this class's.
class QuietHoursWindow {
  final int startMinutes;
  final int endMinutes;

  const QuietHoursWindow({required this.startMinutes, required this.endMinutes});

  @override
  bool operator ==(Object other) =>
      other is QuietHoursWindow && other.startMinutes == startMinutes && other.endMinutes == endMinutes;

  @override
  int get hashCode => Object.hash(startMinutes, endMinutes);

  @override
  String toString() => 'QuietHoursWindow($startMinutes..$endMinutes)';
}

/// Immutable bundle of everything the unlock-time triage check needs,
/// fetched in one [AppSettings.loadSnapshot] call. See that method's doc
/// comment for why retention is excluded.
class AppSettingsSnapshot {
  final bool promptsEnabled;
  final Duration cooldown;
  final double probability;
  final bool quietHoursEnabled;
  final QuietHoursWindow quietHoursWindow;

  const AppSettingsSnapshot({
    required this.promptsEnabled,
    required this.cooldown,
    required this.probability,
    required this.quietHoursEnabled,
    required this.quietHoursWindow,
  });
}

/// How long event history is kept before opportunistic pruning removes it.
/// See `docs/DATA_MODEL.md` §8 — the default is 365 days, chosen so the
/// app's longitudinal "you've improved since you started" story survives a
/// full year, with `forever` available for anyone who wants no cap at all.
enum RetentionPeriod {
  ninetyDays(90),
  oneYear(365),
  forever(-1);

  /// Sentinel stored in `shared_preferences` for [forever] — 0 or a negative
  /// day count has no other meaning, so it's unambiguous and needs no
  /// separate "is this forever" flag alongside the int.
  final int storedDays;

  const RetentionPeriod(this.storedDays);

  static RetentionPeriod fromStoredDays(int days) {
    for (final period in RetentionPeriod.values) {
      if (period.storedDays == days) return period;
    }
    // An unrecognised stored value (shouldn't happen outside manual DB
    // editing) degrades to the default rather than throwing — a corrupt
    // setting must never crash the background engine.
    return AppSettings.defaultRetention;
  }
}
