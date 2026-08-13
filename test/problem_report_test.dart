import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:why_did_i_unlock/problem_report.dart';

void main() {
  setUp(() async {
    // Same in-memory test double used elsewhere for SharedPreferencesAsync
    // (see app_settings_test.dart) — the old SharedPreferences.setMockInitialValues
    // only mocks the legacy sync platform, not SharedPreferencesAsyncPlatform, which
    // is what ProblemReportLog actually uses.
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    await ProblemReportLog.clearForTest();
  });

  test('record + snapshot round-trip includes engine label and error', () async {
    await ProblemReportLog.record('ui', StateError('boom'), StackTrace.current);
    final snap = await ProblemReportLog.snapshotForEmail();
    expect(snap, contains('|ui]'));
    expect(snap, contains('boom'));
  });

  test('empty snapshot explains native crashes leave no Flutter log', () async {
    final snap = await ProblemReportLog.snapshotForEmail();
    expect(snap, contains('No recent in-app errors'));
    expect(snap, contains('native crashes'));
  });

  test('snapshot is clipped to the mailto-safe cap', () async {
    final huge = List.filled(5000, 'x').join();
    await ProblemReportLog.record('overlay', huge);
    final snap = await ProblemReportLog.snapshotForEmail();
    expect(snap.length, lessThanOrEqualTo(ProblemReportLog.maxEmailChars + 1));
  });

  test('breadcrumb + snapshot round-trip includes engine label and message', () async {
    await ProblemReportLog.recordBreadcrumb('background', 'unlock → prompt shown');
    final snap = await ProblemReportLog.snapshotForEmail();
    expect(snap, contains('Recent activity:'));
    expect(snap, contains('|background]'));
    expect(snap, contains('unlock → prompt shown'));
  });

  test('no "Recent activity" header when there are no breadcrumbs', () async {
    final snap = await ProblemReportLog.snapshotForEmail();
    expect(snap, isNot(contains('Recent activity:')));
  });

  test('breadcrumbs and errors are independent buffers — clearing one keeps the other', () async {
    await ProblemReportLog.record('ui', StateError('boom'));
    await ProblemReportLog.recordBreadcrumb('background', 'lock (no overlay up)');
    final snap = await ProblemReportLog.snapshotForEmail();
    expect(snap, contains('boom'));
    expect(snap, contains('lock (no overlay up)'));
  });

  test('breadcrumb buffer rolls over independently of the error buffer\'s cap', () async {
    for (var i = 0; i < 40; i++) {
      await ProblemReportLog.recordBreadcrumb('background', 'event #$i');
    }
    final snap = await ProblemReportLog.snapshotForEmail();
    // Oldest entries pushed out, most recent survives.
    expect(snap, contains('event #39'));
    expect(snap, isNot(contains('event #0\n')));
  });
}
