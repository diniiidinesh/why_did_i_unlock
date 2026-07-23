import 'dart:math';

import 'app_settings.dart' show QuietHoursWindow;

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

/// Suppresses prompts during a configured time-of-day window (e.g. 23:00-07:00
/// — "don't nag me while I'm asleep"). Independent of cooldown/probability —
/// see docs/DATA_MODEL.md §11. The window is a plain value from
/// [QuietHoursWindow] rather than duplicated fields here, so there is exactly
/// one definition of "minutes since local midnight" in the codebase.
///
/// Whether quiet hours applies AT ALL is a separate on/off setting the call
/// site checks (`AppSettingsSnapshot.quietHoursEnabled`) — this class only
/// answers "is `now` inside the configured window," not "is the feature on."
/// Keeping those separate means a user can leave a window configured while
/// toggling the feature off, without losing their chosen times.
class QuietHoursPolicy implements PromptPolicy {
  final QuietHoursWindow window;

  const QuietHoursPolicy(this.window);

  @override
  bool shouldPrompt(PromptContext ctx) => !isWithinWindow(ctx.now, window);

  /// Minute-of-day comparison, deliberately NOT a naive `start <= now <= end`
  /// range check — that form is correct for a same-day window (e.g.
  /// 01:00-05:00) and silently WRONG for one that wraps past midnight (e.g.
  /// 23:00-07:00), where "inside the window" is everything on either side of
  /// midnight, not a single contiguous range on the minute-of-day number
  /// line. See docs/DATA_MODEL.md §11 — this was flagged there specifically
  /// because it's easy to get quietly backwards. Public + static so it's
  /// directly unit-testable without constructing a whole [PromptContext].
  static bool isWithinWindow(DateTime now, QuietHoursWindow window) {
    final minuteOfDay = now.hour * 60 + now.minute;
    if (window.startMinutes == window.endMinutes) {
      // A zero-width window (start == end) is ambiguous between "always
      // quiet" and "never quiet." Treat it as never-quiet — the safer
      // default for a wellbeing app is to fail open (prompt), not silently
      // suppress every single unlock because of a degenerate setting.
      return false;
    }
    if (window.startMinutes < window.endMinutes) {
      // Same-day window: inside is the contiguous range [start, end).
      return minuteOfDay >= window.startMinutes && minuteOfDay < window.endMinutes;
    }
    // Overnight wraparound (start > end): inside is everything from start to
    // midnight, PLUS everything from midnight to end — i.e. NOT the short
    // daytime segment in between.
    return minuteOfDay >= window.startMinutes || minuteOfDay < window.endMinutes;
  }
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
