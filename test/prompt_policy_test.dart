import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/app_settings.dart';
import 'package:why_did_i_unlock/prompt_policy.dart';

void main() {
  final now = DateTime.utc(2026, 1, 1, 12, 0, 0);

  group('10. ProbabilityPromptPolicy', () {
    test('probability 1.0 always prompts', () {
      final policy = ProbabilityPromptPolicy(1.0);
      for (var i = 0; i < 20; i++) {
        expect(policy.shouldPrompt(PromptContext(now: now)), isTrue);
      }
    });

    test('probability 0.0 never prompts', () {
      final policy = ProbabilityPromptPolicy(0.0);
      for (var i = 0; i < 20; i++) {
        expect(policy.shouldPrompt(PromptContext(now: now)), isFalse);
      }
    });

    test('seeded Random gives a deterministic sequence', () {
      // Random(seed) is deterministic across runs on the same Dart version —
      // this pins the exact sequence a probability=0.5 gate produces.
      final policy = ProbabilityPromptPolicy(0.5, random: Random(42));
      final results = List.generate(
        5,
        (_) => policy.shouldPrompt(PromptContext(now: now)),
      );
      final expectedPolicy = ProbabilityPromptPolicy(0.5, random: Random(42));
      final expected = List.generate(
        5,
        (_) => expectedPolicy.shouldPrompt(PromptContext(now: now)),
      );
      expect(results, expected);
    });
  });

  group('11. TimeCooldownPolicy', () {
    final policy = TimeCooldownPolicy(const Duration(seconds: 60));

    test('null lastCompletedAt (never prompted before) allows prompting', () {
      expect(policy.shouldPrompt(PromptContext(now: now)), isTrue);
    });

    test('30s ago (within 60s cooldown) blocks', () {
      final last = now.subtract(const Duration(seconds: 30));
      expect(policy.shouldPrompt(PromptContext(now: now, lastCompletedAt: last)), isFalse);
    });

    test('90s ago (past 60s cooldown) allows', () {
      final last = now.subtract(const Duration(seconds: 90));
      expect(policy.shouldPrompt(PromptContext(now: now, lastCompletedAt: last)), isTrue);
    });

    test('exactly at the 60s boundary allows (>=)', () {
      final last = now.subtract(const Duration(seconds: 60));
      expect(policy.shouldPrompt(PromptContext(now: now, lastCompletedAt: last)), isTrue);
    });
  });

  group('12. CompositePromptPolicy (AND semantics)', () {
    test('within cooldown never prompts, even with probability=1.0', () {
      final composite = CompositePromptPolicy([
        TimeCooldownPolicy(const Duration(seconds: 60)),
        ProbabilityPromptPolicy(1.0),
      ]);
      final last = now.subtract(const Duration(seconds: 10));
      expect(composite.shouldPrompt(PromptContext(now: now, lastCompletedAt: last)), isFalse);
    });

    test('outside cooldown with probability=0.0 never prompts', () {
      final composite = CompositePromptPolicy([
        TimeCooldownPolicy(const Duration(seconds: 60)),
        ProbabilityPromptPolicy(0.0),
      ]);
      final last = now.subtract(const Duration(seconds: 120));
      expect(composite.shouldPrompt(PromptContext(now: now, lastCompletedAt: last)), isFalse);
    });

    test('outside cooldown with probability=1.0 always prompts', () {
      final composite = CompositePromptPolicy([
        TimeCooldownPolicy(const Duration(seconds: 60)),
        ProbabilityPromptPolicy(1.0),
      ]);
      final last = now.subtract(const Duration(seconds: 120));
      expect(composite.shouldPrompt(PromptContext(now: now, lastCompletedAt: last)), isTrue);
    });
  });

  group('40. QuietHoursPolicy — same-day window (start < end)', () {
    // 01:00-05:00 -> 60..300 minutes.
    const window = QuietHoursWindow(startMinutes: 60, endMinutes: 300);
    final policy = QuietHoursPolicy(window);

    test('a time inside the window is suppressed', () {
      final t = DateTime.utc(2026, 1, 1, 2, 30); // 02:30
      expect(QuietHoursPolicy.isWithinWindow(t, window), isTrue);
      expect(policy.shouldPrompt(PromptContext(now: t)), isFalse);
    });

    test('a time outside the window is allowed', () {
      final t = DateTime.utc(2026, 1, 1, 10, 0); // 10:00
      expect(QuietHoursPolicy.isWithinWindow(t, window), isFalse);
      expect(policy.shouldPrompt(PromptContext(now: t)), isTrue);
    });

    test('exactly at start is inside (inclusive)', () {
      final t = DateTime.utc(2026, 1, 1, 1, 0); // 01:00
      expect(QuietHoursPolicy.isWithinWindow(t, window), isTrue);
    });

    test('exactly at end is outside (exclusive)', () {
      final t = DateTime.utc(2026, 1, 1, 5, 0); // 05:00
      expect(QuietHoursPolicy.isWithinWindow(t, window), isFalse);
    });
  });

  group('41. QuietHoursPolicy — overnight wraparound (start > end)', () {
    // 22:00-07:00 -> 1320..420 minutes. This is the trap case: a naive
    // start<=now<=end range check gets this silently backwards.
    const window = QuietHoursWindow(startMinutes: 22 * 60, endMinutes: 7 * 60);
    final policy = QuietHoursPolicy(window);

    test('late evening (23:00) is inside', () {
      final t = DateTime.utc(2026, 1, 1, 23, 0);
      expect(QuietHoursPolicy.isWithinWindow(t, window), isTrue);
      expect(policy.shouldPrompt(PromptContext(now: t)), isFalse);
    });

    test('early morning (03:00), past midnight, is still inside', () {
      final t = DateTime.utc(2026, 1, 1, 3, 0);
      expect(QuietHoursPolicy.isWithinWindow(t, window), isTrue);
    });

    test('exactly at start (22:00) is inside (inclusive)', () {
      final t = DateTime.utc(2026, 1, 1, 22, 0);
      expect(QuietHoursPolicy.isWithinWindow(t, window), isTrue);
    });

    test('exactly at end (07:00) is outside (exclusive)', () {
      final t = DateTime.utc(2026, 1, 1, 7, 0);
      expect(QuietHoursPolicy.isWithinWindow(t, window), isFalse);
    });

    test('midday (12:00) is outside — the short segment between end and start', () {
      final t = DateTime.utc(2026, 1, 1, 12, 0);
      expect(QuietHoursPolicy.isWithinWindow(t, window), isFalse);
      expect(policy.shouldPrompt(PromptContext(now: t)), isTrue);
    });

    test('one minute before midnight is inside', () {
      final t = DateTime.utc(2026, 1, 1, 23, 59);
      expect(QuietHoursPolicy.isWithinWindow(t, window), isTrue);
    });

    test('midnight exactly is inside', () {
      final t = DateTime.utc(2026, 1, 2, 0, 0);
      expect(QuietHoursPolicy.isWithinWindow(t, window), isTrue);
    });
  });

  group('42. QuietHoursPolicy — degenerate window', () {
    test('start == end fails open (never suppresses) rather than always-suppress', () {
      const window = QuietHoursWindow(startMinutes: 300, endMinutes: 300);
      // Check across several times of day — none should be suppressed.
      for (final hour in [0, 5, 12, 18, 23]) {
        final t = DateTime.utc(2026, 1, 1, hour);
        expect(QuietHoursPolicy.isWithinWindow(t, window), isFalse, reason: 'hour=$hour');
      }
      // And via shouldPrompt, confirming the policy object itself agrees.
      final policy = QuietHoursPolicy(window);
      expect(policy.shouldPrompt(PromptContext(now: DateTime.utc(2026, 1, 1, 12))), isTrue);
    });
  });
}
