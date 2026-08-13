import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-only buffer of recent Flutter/async errors for closed-test
/// "Report a problem" emails — no network, no Crashlytics.
///
/// Survives soft failures and process restarts via [SharedPreferencesAsync].
/// Does **not** capture hard native crashes (OOM, SIGSEGV); those leave no
/// Dart stack — the email body explains that to the reporter.
///
/// Deliberately uses [SharedPreferencesAsync], never `SharedPreferences.getInstance()`
/// — same reasoning as `AppSettings` (see that class's doc comment).
/// `installHooks()` runs in three separate isolates (`ui`/`background`/`overlay`,
/// see `lib/main.dart`), and `getInstance()`'s cached per-isolate singleton
/// previously caused two real bugs here: the About screen (UI isolate) could
/// read a stale cached copy that never saw errors recorded later by the
/// background isolate in the same session, and — because `record()` does a
/// read-modify-write — an isolate with a stale cached read could clobber
/// every entry another isolate had written since. `SharedPreferencesAsync`
/// reads the platform directly on every call, closing both gaps for the UI
/// and background isolates.
///
/// The overlay isolate is a separate, unresolved problem: it has no plugins
/// registered at all (see `lib/main.dart`'s note on `backgroundMain`), so
/// **no** `shared_preferences` call — sync or async — works there; `record()`
/// silently no-ops via the catch below whenever called from that isolate.
/// Capturing overlay-isolate errors needs a relay through the background
/// isolate's `IsolateNameServer` ports (the same pattern `_intentWritePortName`
/// uses), not a plugin swap — tracked in `docs/BACKLOG.md`, not yet built.
class ProblemReportLog {
  static const prefsKey = 'problem_report_log_v1';

  /// Cap stored blob so prefs stay small.
  static const maxStoredChars = 2400;

  /// Cap what we put in a mailto: body (many mail apps truncate long URIs).
  static const maxEmailChars = 1600;

  /// Separate key/rolling buffer from [prefsKey] — breadcrumbs are one-line
  /// lifecycle notes ("unlock → skipped (cooldown)"), not exceptions, and
  /// sharing a buffer with stack traces would let a burst of the (far more
  /// common) former crowd out the latter, which is the whole reason to
  /// distinguish "what broke" (errors) from "what happened before it broke"
  /// (breadcrumbs) in the first place.
  static const breadcrumbsPrefsKey = 'problem_report_breadcrumbs_v1';

  /// Smaller cap than [maxStoredChars] on purpose — breadcrumbs are terse
  /// one-liners, not stack traces, so this still holds ~15-20 recent events.
  static const maxStoredBreadcrumbChars = 1000;

  /// Append one error. Safe to call from any isolate with plugin access
  /// (UI/background — NOT the overlay isolate, see the class doc comment).
  static Future<void> record(String engine, Object error, [StackTrace? stack]) async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    final entry = '[$stamp|$engine]\n'
        '${_clip(error.toString(), 400)}\n'
        '${_clip(stack?.toString() ?? '', 800)}\n---\n';
    try {
      final prefs = SharedPreferencesAsync();
      final prev = await prefs.getString(prefsKey) ?? '';
      var next = '$prev$entry';
      if (next.length > maxStoredChars) {
        next = next.substring(next.length - maxStoredChars);
      }
      await prefs.setString(prefsKey, next);
    } catch (_) {
      // Never let diagnostics break the app.
    }
  }

  /// Append one breadcrumb: a short, no-stack-trace note on something the
  /// app did (an unlock's outcome, a bubble lifecycle event) — not an error.
  /// Deliberately takes a short freeform [message] rather than structured
  /// fields, and deliberately does NOT accept user-declared intent text as
  /// an argument anywhere it's called from — see call sites in `lib/main.dart`
  /// for the events this covers. Same fire-and-forget, never-throws contract
  /// as [record]; same isolate caveat (see the class doc comment) — the
  /// overlay isolate can't call this directly, but its events reach here via
  /// the `'breadcrumb'` relay message type in `backgroundMain`'s
  /// `intentWritePort` listener, since that already exists for the overlay's
  /// declare/dismiss/snooze relays and needed no new plumbing to reuse.
  static Future<void> recordBreadcrumb(String engine, String message) async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    final entry = '[$stamp|$engine] ${_clip(message, 200)}\n';
    try {
      final prefs = SharedPreferencesAsync();
      final prev = await prefs.getString(breadcrumbsPrefsKey) ?? '';
      var next = '$prev$entry';
      if (next.length > maxStoredBreadcrumbChars) {
        next = next.substring(next.length - maxStoredBreadcrumbChars);
      }
      await prefs.setString(breadcrumbsPrefsKey, next);
    } catch (_) {
      // Never let diagnostics break the app.
    }
  }

  /// Text block for a problem-report email body. Breadcrumbs are listed
  /// first (chronological lead-up) and are omitted entirely when there are
  /// none, rather than printing an empty "Recent activity:" header — most
  /// reports from a freshly-installed or freshly-cleared device won't have
  /// any yet, and an empty section reads as broken rather than as "nothing
  /// happened to log," unlike the errors section's explicit empty-state copy
  /// below (errors are the section a tester is specifically asked about, so
  /// that one stays explicit either way).
  static Future<String> snapshotForEmail() async {
    try {
      final prefs = SharedPreferencesAsync();
      final breadcrumbs = (await prefs.getString(breadcrumbsPrefsKey) ?? '').trim();
      final raw = await prefs.getString(prefsKey) ?? '';
      final errorsSection = raw.trim().isEmpty
          ? '(No recent in-app errors were captured. If the app closed '
              'abruptly with no dialog, describe what you were doing above — '
              'native crashes leave no Flutter log on the device.)'
          : raw;
      final buffer = StringBuffer();
      if (breadcrumbs.isNotEmpty) {
        buffer.writeln('Recent activity:');
        buffer.writeln(breadcrumbs);
        buffer.writeln();
      }
      buffer.writeln('Recent in-app errors:');
      buffer.write(errorsSection);
      return _clip(buffer.toString(), maxEmailChars);
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
    await SharedPreferencesAsync().remove(prefsKey);
    await SharedPreferencesAsync().remove(breadcrumbsPrefsKey);
  }
}
