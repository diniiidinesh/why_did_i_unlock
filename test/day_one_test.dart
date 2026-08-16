import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:why_did_i_unlock/app_settings.dart';
import 'package:why_did_i_unlock/day_one.dart';
import 'package:why_did_i_unlock/day_one_notifications.dart';
import 'package:why_did_i_unlock/intent_store.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16, 12);

  group('DayOneNudge.recapIsDue', () {
    test('false before 24h', () {
      expect(
        DayOneNudge.recapIsDue(
          now: now,
          firstLaunchAtMs: now.subtract(const Duration(hours: 23, minutes: 59)).millisecondsSinceEpoch,
          onboardingCompleted: true,
          recapSeen: false,
        ),
        isFalse,
      );
    });

    test('true at the 24h boundary', () {
      expect(
        DayOneNudge.recapIsDue(
          now: now,
          firstLaunchAtMs: now.subtract(DayOneNudge.delay).millisecondsSinceEpoch,
          onboardingCompleted: true,
          recapSeen: false,
        ),
        isTrue,
      );
    });

    test('false when recap already seen — fires once', () {
      expect(
        DayOneNudge.recapIsDue(
          now: now,
          firstLaunchAtMs: now.subtract(const Duration(days: 3)).millisecondsSinceEpoch,
          onboardingCompleted: true,
          recapSeen: true,
        ),
        isFalse,
      );
    });

    test('false while onboarding is incomplete or stamp is missing', () {
      expect(
        DayOneNudge.recapIsDue(
          now: now,
          firstLaunchAtMs: now.subtract(const Duration(days: 2)).millisecondsSinceEpoch,
          onboardingCompleted: false,
          recapSeen: false,
        ),
        isFalse,
      );
      expect(
        DayOneNudge.recapIsDue(
          now: now,
          firstLaunchAtMs: null,
          onboardingCompleted: true,
          recapSeen: false,
        ),
        isFalse,
      );
    });
  });

  group('DayOneNudge.shouldNotify', () {
    test('posts only when due, opted in, permitted, and not yet posted', () {
      expect(
        DayOneNudge.shouldNotify(
          recapDue: true,
          reminderEnabled: true,
          notificationPosted: false,
          permissionGranted: true,
        ),
        isTrue,
      );
    });

    test('permission denied still allows in-app recap, not the notification', () {
      expect(
        DayOneNudge.shouldNotify(
          recapDue: true,
          reminderEnabled: true,
          notificationPosted: false,
          permissionGranted: false,
        ),
        isFalse,
      );
      expect(
        DayOneNudge.recapIsDue(
          now: now,
          firstLaunchAtMs: now.subtract(DayOneNudge.delay).millisecondsSinceEpoch,
          onboardingCompleted: true,
          recapSeen: false,
        ),
        isTrue,
      );
    });

    test('opt-out and already-posted both skip the notification', () {
      expect(
        DayOneNudge.shouldNotify(
          recapDue: true,
          reminderEnabled: false,
          notificationPosted: false,
          permissionGranted: true,
        ),
        isFalse,
      );
      expect(
        DayOneNudge.shouldNotify(
          recapDue: true,
          reminderEnabled: true,
          notificationPosted: true,
          permissionGranted: true,
        ),
        isFalse,
      );
    });
  });

  group('DayOneStats.mostCommonReasonFrom', () {
    IntentEvent event(String id, String text, {IntentKind kind = IntentKind.intent}) {
      final at = DateTime.utc(2026, 8, 16);
      return IntentEvent(
        clientId: id,
        kind: kind,
        source: kind == IntentKind.intent ? IntentSource.preset : null,
        text: text,
        declaredAt: at,
        completedAt: at,
      );
    }

    test('picks the most frequent declared text and ignores Just Like That', () {
      expect(
        DayOneStats.mostCommonReasonFrom([
          event('1', 'Check mail'),
          event('2', 'Check mail'),
          event('3', 'Pay someone'),
          event('4', 'Just Like That', kind: IntentKind.noIntent),
        ]),
        'Check mail',
      );
    });

    test('tie breaks alphabetically; empty list is null', () {
      expect(DayOneStats.mostCommonReasonFrom([]), isNull);
      expect(
        DayOneStats.mostCommonReasonFrom([
          event('1', 'Pay someone'),
          event('2', 'Check mail'),
        ]),
        'Check mail',
      );
    });
  });

  group('DayOneStats.load uses existing queries', () {
    late IntentStore store;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      store = await IntentStore.open(path: inMemoryDatabasePath);
    });

    tearDown(() async => store.close());

    test('unlocks, declared intents, purposeless, and most common reason', () async {
      final now = DateTime.utc(2026, 8, 16, 12);
      await store.insertUnlock(unlockedAt: now, promptShown: true);
      await store.insertUnlock(unlockedAt: now, promptShown: true);
      await store.insertEvent(IntentEvent(
        clientId: 'a',
        kind: IntentKind.intent,
        source: IntentSource.preset,
        text: 'Check mail',
        declaredAt: now,
        completedAt: now,
      ));
      await store.insertEvent(IntentEvent(
        clientId: 'b',
        kind: IntentKind.intent,
        source: IntentSource.preset,
        text: 'Check mail',
        declaredAt: now,
        completedAt: now,
      ));
      await store.insertEvent(IntentEvent(
        clientId: 'c',
        kind: IntentKind.noIntent,
        source: null,
        text: 'Just Like That',
        declaredAt: now,
        completedAt: now,
      ));

      final stats = await DayOneStats.load(store, now: now);
      expect(stats.unlockCount, 2);
      expect(stats.intentsDeclared, 2);
      expect(stats.purposelessCount, 1);
      expect(stats.mostCommonReason, 'Check mail');
    });
  });

  group('maybePostDayOneNotification', () {
    late AppSettings settings;

    setUp(() {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      settings = const AppSettings();
    });

    test('posts once then not again', () async {
      final now = DateTime.utc(2026, 8, 17, 12);
      await settings.setOnboardingCompleted(true);
      await settings.ensureFirstLaunchAt(DateTime.utc(2026, 8, 16, 12));
      var shows = 0;
      await maybePostDayOneNotification(
        settings: settings,
        now: now,
        notificationsGranted: () async => true,
        show: () async { shows++; },
      );
      expect(shows, 1);
      expect(await settings.dayOneNotificationPosted(), isTrue);

      await maybePostDayOneNotification(
        settings: settings,
        now: now,
        notificationsGranted: () async => true,
        show: () async { shows++; },
      );
      expect(shows, 1);
    });

    test('permission-denied path never posts; recap remains due', () async {
      final now = DateTime.utc(2026, 8, 17, 12);
      await settings.setOnboardingCompleted(true);
      await settings.ensureFirstLaunchAt(DateTime.utc(2026, 8, 16, 12));
      var shows = 0;
      await maybePostDayOneNotification(
        settings: settings,
        now: now,
        notificationsGranted: () async => false,
        show: () async { shows++; },
      );
      expect(shows, 0);
      expect(await settings.dayOneNotificationPosted(), isFalse);
      expect(
        await dayOneRecapShouldShow(settings, now),
        isTrue,
      );
    });
  });
}
