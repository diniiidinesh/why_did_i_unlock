import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_settings.dart';
import 'brand.dart';
import 'day_one.dart';

/// Local (on-device) day-1 recap reminder. **Background engine only** —
/// never call from overlay-isolate code (`docs/ARCHITECTURE.md` §5; overlay
/// has no plugins). No `zonedSchedule`, no exact-alarm, no boot reschedule:
/// [maybePostDayOneNotification] is evaluated on the existing unlock path
/// (`docs/erd/onboarding-revamp-2026-08-15.md` §4D.2).
class DayOneNotifications {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const channelId = 'beacon_day_one';
  static const notificationId = 41;

  static Future<void> initialize() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            channelId,
            'First-day recap',
            description: 'A one-time reminder to look at your first day with Beacon.',
            importance: Importance.defaultImportance,
          ),
        );
    _ready = true;
  }

  static Future<void> showRecapReminder() async {
    await initialize();
    await _plugin.show(
      notificationId,
      'Your first day with $appDisplayName',
      'See what you actually unlocked for.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'First-day recap',
          channelDescription: 'A one-time reminder to look at your first day with Beacon.',
          importance: Importance.defaultImportance,
        ),
      ),
    );
  }
}

/// Fire-and-forget from the unlock handler. Plugin / permission failures are
/// swallowed — losing the reminder is cheaper than delaying the prompt, and
/// the in-app recap still runs on next launch (`§4D.3`).
Future<void> maybePostDayOneNotification({
  AppSettings settings = const AppSettings(),
  DateTime? now,
  Future<bool> Function()? notificationsGranted,
  Future<void> Function()? show,
}) async {
  try {
    final clock = now ?? DateTime.now();
    final results = await (
      settings.onboardingCompleted(),
      settings.dayOneNudgeShown(),
      settings.firstLaunchAtMs(),
      settings.dayOneReminderEnabled(),
      settings.dayOneNotificationPosted(),
    ).wait;

    final due = DayOneNudge.recapIsDue(
      now: clock,
      firstLaunchAtMs: results.$3,
      onboardingCompleted: results.$1,
      recapSeen: results.$2,
    );
    final granted = await (notificationsGranted ?? _defaultNotificationsGranted)();
    if (!DayOneNudge.shouldNotify(
      recapDue: due,
      reminderEnabled: results.$4,
      notificationPosted: results.$5,
      permissionGranted: granted,
    )) {
      return;
    }

    await (show ?? DayOneNotifications.showRecapReminder)();
    await settings.setDayOneNotificationPosted(true);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('⚠️ day-1 notification skipped: $e');
    }
  }
}

Future<bool> _defaultNotificationsGranted() async {
  final status = await Permission.notification.status;
  // Pre-Android-13 devices have no runtime POST_NOTIFICATIONS gate; treat
  // as granted so the reminder can still post. Denied / permanentlyDenied
  // fall through to the in-app recap.
  return status.isGranted || status.isLimited || status.isProvisional;
}
