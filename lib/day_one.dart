import 'app_settings.dart';
import 'intent_store.dart';

/// Day-1 recap gating (`docs/erd/onboarding-revamp-2026-08-15.md` §4D).
///
/// Pure Dart so tests cover the 24h boundary and the "fires once" rule
/// without a plugin. The background engine posts a local notification when
/// [shouldNotify] is true; [AppLauncher] shows the recap screen when
/// [recapIsDue] is true — even if the notification never went out.
class DayOneNudge {
  static const Duration delay = Duration(hours: 24);

  /// In-app recap is due once, after onboarding, 24h from first launch.
  /// [firstLaunchAtMs] null means we have not yet stamped a start — not due.
  static bool recapIsDue({
    required DateTime now,
    required int? firstLaunchAtMs,
    required bool onboardingCompleted,
    required bool recapSeen,
    Duration delay = delay,
  }) {
    if (!onboardingCompleted || recapSeen) return false;
    if (firstLaunchAtMs == null) return false;
    final first = DateTime.fromMillisecondsSinceEpoch(firstLaunchAtMs);
    return !now.difference(first).isNegative && now.difference(first) >= delay;
  }

  /// Local notification may fire only when the recap itself is due, the user
  /// opted in, permission is granted, and we have not posted yet.
  /// Opt-out / permission-denied still get the in-app recap via [recapIsDue].
  static bool shouldNotify({
    required bool recapDue,
    required bool reminderEnabled,
    required bool notificationPosted,
    required bool permissionGranted,
  }) {
    return recapDue && reminderEnabled && !notificationPosted && permissionGranted;
  }
}

/// First-day numbers from **existing** [IntentStore] queries — no new SQL
/// (§4C.5). [load] uses [IntentStore.userDataCounts], [IntentStore.outcomeBreakdown],
/// and [IntentStore.recentEvents]; "most common reason" is grouped in Dart.
class DayOneStats {
  final int unlockCount;
  final int intentsDeclared;
  final int purposelessCount;
  final String? mostCommonReason;

  const DayOneStats({
    required this.unlockCount,
    required this.intentsDeclared,
    required this.purposelessCount,
    required this.mostCommonReason,
  });

  static const empty = DayOneStats(
    unlockCount: 0,
    intentsDeclared: 0,
    purposelessCount: 0,
    mostCommonReason: null,
  );

  static Future<DayOneStats> load(IntentStore store, {DateTime? now}) async {
    final clock = now ?? DateTime.now();
    final counts = await store.userDataCounts();
    final outcomes = await store.outcomeBreakdown(window: InsightWindow.last30Days, now: clock);
    final events = await store.recentEvents(limit: 50);

    var intentsDeclared = 0;
    var purposeless = 0;
    for (final row in outcomes) {
      if (row.category == OutcomeCategory.noIntent) {
        purposeless += row.count;
      } else {
        intentsDeclared += row.count;
      }
    }

    return DayOneStats(
      unlockCount: counts.unlockCount,
      intentsDeclared: intentsDeclared,
      purposelessCount: purposeless,
      mostCommonReason: mostCommonReasonFrom(events),
    );
  }

  /// Highest count among [IntentKind.intent] texts. Ties break alphabetically
  /// so the result is stable across runs. Null when nothing was declared.
  static String? mostCommonReasonFrom(List<IntentEvent> events) {
    final counts = <String, int>{};
    for (final event in events) {
      if (event.kind != IntentKind.intent) continue;
      final text = event.text.trim();
      if (text.isEmpty) continue;
      counts[text] = (counts[text] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final best = counts.entries.reduce((a, b) {
      if (b.value != a.value) return b.value > a.value ? b : a;
      return a.key.compareTo(b.key) <= 0 ? a : b;
    });
    return best.key;
  }
}

/// Shared "should the launcher show the recap?" helper — same inputs as
/// [DayOneNudge.recapIsDue], loaded from [AppSettings].
Future<bool> dayOneRecapShouldShow(AppSettings settings, DateTime now) async {
  final results = await (
    settings.onboardingCompleted(),
    settings.dayOneNudgeShown(),
    settings.firstLaunchAtMs(),
  ).wait;
  return DayOneNudge.recapIsDue(
    now: now,
    firstLaunchAtMs: results.$3,
    onboardingCompleted: results.$1,
    recapSeen: results.$2,
  );
}
