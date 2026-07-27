import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only buffer of recent Flutter/async errors for closed-test
/// "Report a problem" emails — no network, no Crashlytics.
///
/// Survives soft failures and process restarts via [SharedPreferences].
/// Does **not** capture hard native crashes (OOM, SIGSEGV); those leave no
/// Dart stack — the email body explains that to the reporter.
class ProblemReportLog {
  static const prefsKey = 'problem_report_log_v1';

  /// Cap stored blob so prefs stay small.
  static const maxStoredChars = 2400;

  /// Cap what we put in a mailto: body (many mail apps truncate long URIs).
  static const maxEmailChars = 1600;

  /// Append one error. Safe to call from any isolate that has prefs.
  static Future<void> record(String engine, Object error, [StackTrace? stack]) async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    final entry = '[$stamp|$engine]\n'
        '${_clip(error.toString(), 400)}\n'
        '${_clip(stack?.toString() ?? '', 800)}\n---\n';
    try {
      final prefs = await SharedPreferences.getInstance();
      final prev = prefs.getString(prefsKey) ?? '';
      var next = '$prev$entry';
      if (next.length > maxStoredChars) {
        next = next.substring(next.length - maxStoredChars);
      }
      await prefs.setString(prefsKey, next);
    } catch (_) {
      // Never let diagnostics break the app.
    }
  }

  /// Text block for a problem-report email body.
  static Future<String> snapshotForEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(prefsKey) ?? '';
      if (raw.trim().isEmpty) {
        return '(No recent in-app errors were captured. If the app closed '
            'abruptly with no dialog, describe what you were doing above — '
            'native crashes leave no Flutter log on the device.)';
      }
      return _clip(raw, maxEmailChars);
    } catch (_) {
      return '(Could not read the local error log.)';
    }
  }

  /// Install Flutter + platform error hooks for this isolate/engine.
  ///
  /// [engine] labels the source in the log (`ui` / `background` / `overlay`).
  /// Async errors are marked handled so the process can stay alive long
  /// enough for the user to open About → Report a problem.
  static void installHooks(String engine) {
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      unawaited(record(engine, details.exceptionAsString(), details.stack));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(record(engine, error, stack));
      return true;
    };
  }

  static String _clip(String s, int max) {
    if (s.length <= max) return s;
    return '${s.substring(0, max)}…';
  }

  /// Test helper.
  @visibleForTesting
  static Future<void> clearForTest() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}
