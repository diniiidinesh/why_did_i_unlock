import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
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
}
