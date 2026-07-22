import 'dart:math';

/// Everything a [PromptPolicy] might need to decide whether to show the
/// capture screen on this unlock. Only [now] and [lastCompletedAt] are
/// populated by the MVP call site (`_showCaptureScreen` in main.dart);
/// [recentCount] exists so a future instance-based policy (e.g. "skip every
/// other unlock") can plug in later without changing that call site.
class PromptContext {
  final DateTime now;
  final DateTime? lastCompletedAt;
  final int? recentCount;

  const PromptContext({
    required this.now,
    this.lastCompletedAt,
    this.recentCount,
  });
}

/// Decides whether the capture screen should be shown for a given unlock.
/// The seam that lets prompt-frequency triage evolve (time / probability /
/// instance-based, or a future settings-driven combination of them) without
/// touching `_showCaptureScreen`'s call site — see the Sprint 3 plan's
/// rationale on why an unlock-every-time prompt causes habituation.
abstract class PromptPolicy {
  bool shouldPrompt(PromptContext ctx);
}

/// A deterministic floor: never prompt within [cooldown] of the last
/// completed event (intent OR no-intent — both represent user engagement
/// with the prompt). This is what kills back-to-back nagging; it does NOT by
/// itself vary timing (see [ProbabilityPromptPolicy] for that).
class TimeCooldownPolicy implements PromptPolicy {
  final Duration cooldown;

  const TimeCooldownPolicy(this.cooldown);

  @override
  bool shouldPrompt(PromptContext ctx) {
    final last = ctx.lastCompletedAt;
    if (last == null) return true;
    return ctx.now.difference(last) >= cooldown;
  }
}

/// Prompts on a random subset of unlocks. Unpredictable timing resists the
/// habituation a fixed cadence produces (see plan rationale — Vance &
/// Anderson, MISQ 2018). [random] is injectable so tests can assert exact
/// behavior with a seeded generator instead of real randomness.
class ProbabilityPromptPolicy implements PromptPolicy {
  final double probability;
  final Random _random;

  ProbabilityPromptPolicy(this.probability, {Random? random}) : _random = random ?? Random();

  @override
  bool shouldPrompt(PromptContext ctx) => _random.nextDouble() < probability;
}

/// ANDs a list of policies together — prompts only if ALL agree. This is the
/// actual extensibility point: adding a new triage strategy later (or a
/// settings screen letting the user toggle strategies) is a new list element
/// or a rebuilt list, never a change to how `_showCaptureScreen` calls it.
class CompositePromptPolicy implements PromptPolicy {
  final List<PromptPolicy> policies;

  const CompositePromptPolicy(this.policies);

  @override
  bool shouldPrompt(PromptContext ctx) => policies.every((p) => p.shouldPrompt(ctx));
}
