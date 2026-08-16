import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app_settings.dart';
import 'brand.dart';
import 'day_one.dart';

/// Posted from the **background** engine on the unlock path. Tap handling
/// is on the **main UI** isolate (`AppLauncher`) so a shade tap opens the
/// same recap as an icon open. Never call from overlay-isolate code
/// (`docs/ARCHITECTURE.md` §5). No `zonedSchedule`, no exact-alarm, no boot
/// reschedule: [maybePostDayOneNotification] piggybacks the existing unlock
/// handler (`docs/erd/onboarding-revamp-2026-08-15.md` §4D.2).
class DayOneNotifications {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static void Function()? _uiTapHandler;

  static const channelId = 'beacon_day_one';
  static const notificationId = 41;
  /// Identifies this reminder in tap callbacks so we don't react to the
  /// overlay foreground-service notification.
  static const recapPayload = 'day_one_recap';

  /// Tap handler lives on the **main UI** isolate (`AppLauncher`). Posting
  /// still happens in the background engine — each isolate has its own
  /// plugin instance. The callback reads [_uiTapHandler] at tap time so a
  /// later [bindUiTapHandler] still works if [initialize] ran first.
  static Future<void> initialize({void Function()? onRecapTapped}) async {
    if (onRecapTapped != null) _uiTapHandler = onRecapTapped;
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: android),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload == recapPayload) _uiTapHandler?.call();
      },
    );
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
      payload: recapPayload,
    );
  }

  /// [AppLauncher] registers this so a shade tap while Home is already up
  /// still opens the recap (a killed-process tap is handled by recap-due
  /// in `_load`).
  static void bindUiTapHandler(void Function() onTap) {
    _uiTapHandler = onTap;
    unawaited(initialize(onRecapTapped: onTap).catchError((_) {}));
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
