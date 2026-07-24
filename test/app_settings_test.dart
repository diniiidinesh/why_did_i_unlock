import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:why_did_i_unlock/app_settings.dart';

void main() {
  late AppSettings settings;

  setUp(() {
    // Same in-memory test double used by widget_test.dart — no real platform
    // channel involved, and (crucially) each test gets a fresh empty store,
    // so defaults are genuinely exercised rather than leaking state.
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    settings = const AppSettings();
  });

  group('30. defaults match the pre-Settings-screen hardcoded constants', () {
    test('promptsEnabled defaults true', () async {
      expect(await settings.promptsEnabled(), isTrue);
    });

    test('cooldownMinutes defaults to 1 (matches main.dart intentCooldown)', () async {
      expect(await settings.cooldownMinutes(), 1);
    });

    test('promptProbability defaults to 1.0 (ask every unlock once cooldown clears)', () async {
      expect(await settings.promptProbability(), 1.0);
    });

    test('quietHoursEnabled defaults false', () async {
      expect(await settings.quietHoursEnabled(), isFalse);
    });

    test('retentionPeriod defaults to oneYear', () async {
      expect(await settings.retentionPeriod(), RetentionPeriod.oneYear);
    });

    test('onboardingCompleted defaults false — a fresh install shows onboarding', () async {
      expect(await settings.onboardingCompleted(), isFalse);
    });
  });

  group('31. round-trips', () {
    test('promptsEnabled', () async {
      await settings.setPromptsEnabled(false);
      expect(await settings.promptsEnabled(), isFalse);
    });

    test('cooldownMinutes within range', () async {
      await settings.setCooldownMinutes(15);
      expect(await settings.cooldownMinutes(), 15);
    });

    test('promptProbability within range', () async {
      await settings.setPromptProbability(0.75);
      expect(await settings.promptProbability(), 0.75);
    });

    test('quietHoursWindow', () async {
      const window = QuietHoursWindow(startMinutes: 23 * 60, endMinutes: 6 * 60);
      await settings.setQuietHoursWindow(window);
      expect(await settings.quietHoursWindow(), window);
    });

    test('retentionPeriod', () async {
      await settings.setRetentionPeriod(RetentionPeriod.forever);
      expect(await settings.retentionPeriod(), RetentionPeriod.forever);
    });

    test('onboardingCompleted', () async {
      await settings.setOnboardingCompleted(true);
      expect(await settings.onboardingCompleted(), isTrue);
    });

    test('a second AppSettings instance sees an onboarding-completed write immediately', () async {
      // Same cross-isolate-visibility guarantee as the other settings —
      // T4's onboarding flow runs in the main UI engine; _showCaptureScreen's
      // eventual read of this (if ever needed) runs in the background
      // engine. Confirms this flag isn't accidentally special-cased.
      await settings.setOnboardingCompleted(true);
      final other = const AppSettings();
      expect(await other.onboardingCompleted(), isTrue);
    });
  });

  group('32. clamping — enforced at the storage layer, not just the UI', () {
    test('cooldown above the max is clamped down on write', () async {
      await settings.setCooldownMinutes(999);
      expect(await settings.cooldownMinutes(), AppSettings.cooldownMaxMinutes);
    });

    test('cooldown below the min is clamped up on write', () async {
      await settings.setCooldownMinutes(-5);
      expect(await settings.cooldownMinutes(), AppSettings.cooldownMinMinutes);
    });

    test('probability above the max is clamped down on write', () async {
      await settings.setPromptProbability(1.5);
      expect(await settings.promptProbability(), AppSettings.probabilityMax);
    });

    test('probability below the min is clamped up on write', () async {
      await settings.setPromptProbability(0.0);
      expect(await settings.promptProbability(), AppSettings.probabilityMin);
    });

    test('a value written by an out-of-band mechanism is clamped on READ too, not just on write', () async {
      // Seeds the store directly (bypassing every AppSettings setter) to
      // simulate a value that predates a bound change, or that a bug/manual
      // edit wrote out of range. The GETTER must not trust storage blindly —
      // this is the read-side half of the write-side clamp tested above.
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.withData({
        'cooldown_minutes': 999,
        'prompt_probability': 1.5,
      });
      expect(await settings.cooldownMinutes(), AppSettings.cooldownMaxMinutes);
      expect(await settings.promptProbability(), AppSettings.probabilityMax);
    });

    test('quiet hours minute-of-day is clamped into 0..1439 on write', () async {
      await settings.setQuietHoursWindow(const QuietHoursWindow(startMinutes: -30, endMinutes: 2000));
      final window = await settings.quietHoursWindow();
      expect(window.startMinutes, 0);
      expect(window.endMinutes, 24 * 60 - 1);
    });
  });

  group('33. retention period mapping', () {
    test('every enum value round-trips through storage', () async {
      for (final period in RetentionPeriod.values) {
        await settings.setRetentionPeriod(period);
        expect(await settings.retentionPeriod(), period, reason: period.name);
      }
    });

    test('fromStoredDays never throws on a bogus value', () {
      expect(RetentionPeriod.fromStoredDays(42), AppSettings.defaultRetention);
    });

    test('forever uses a negative sentinel, distinguishable from any real day count', () {
      expect(RetentionPeriod.forever.storedDays, lessThan(0));
      expect(RetentionPeriod.ninetyDays.storedDays, greaterThan(0));
      expect(RetentionPeriod.oneYear.storedDays, greaterThan(0));
    });
  });

  group('35. quiet hours enabled flag is independent of the window', () {
    test('toggling the flag off preserves the configured window', () async {
      const window = QuietHoursWindow(startMinutes: 23 * 60, endMinutes: 6 * 60);
      await settings.setQuietHoursWindow(window);
      await settings.setQuietHoursEnabled(true);
      await settings.setQuietHoursEnabled(false);

      expect(await settings.quietHoursEnabled(), isFalse);
      expect(await settings.quietHoursWindow(), window);
    });
  });

  group('34. loadSnapshot', () {
    test('reflects defaults with nothing stored', () async {
      final snap = await settings.loadSnapshot();
      expect(snap.promptsEnabled, isTrue);
      expect(snap.cooldown, const Duration(minutes: 1));
      expect(snap.probability, 1.0);
      expect(snap.quietHoursEnabled, isFalse);
    });

    test('reflects writes made before the snapshot is taken', () async {
      await settings.setPromptsEnabled(false);
      await settings.setCooldownMinutes(10);
      await settings.setPromptProbability(0.9);
      await settings.setQuietHoursEnabled(true);
      await settings.setQuietHoursWindow(const QuietHoursWindow(startMinutes: 60, endMinutes: 120));

      final snap = await settings.loadSnapshot();
      expect(snap.promptsEnabled, isFalse);
      expect(snap.cooldown, const Duration(minutes: 10));
      expect(snap.probability, 0.9);
      expect(snap.quietHoursEnabled, isTrue);
      expect(snap.quietHoursWindow, const QuietHoursWindow(startMinutes: 60, endMinutes: 120));
    });

    test('a second, independent AppSettings instance sees the same values', () async {
      // The whole point of never caching SharedPreferencesAsync: a write from
      // one "isolate" (simulated here by a second instance) must be visible
      // to a read from another, immediately.
      await settings.setCooldownMinutes(20);
      final other = const AppSettings();
      expect(await other.cooldownMinutes(), 20);
    });
  });
}
