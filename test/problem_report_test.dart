import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:why_did_i_unlock/problem_report.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
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
}
