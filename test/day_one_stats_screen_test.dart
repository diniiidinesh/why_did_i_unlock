import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:why_did_i_unlock/day_one_stats_screen.dart';
import 'package:why_did_i_unlock/intent_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('renders counts from the injected store and Continue fires onFinished', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    late IntentStore store;
    final now = DateTime.utc(2026, 8, 16, 12);
    await tester.runAsync(() async {
      store = await IntentStore.open(path: inMemoryDatabasePath);
      await store.insertUnlock(unlockedAt: now, promptShown: true);
      await store.insertEvent(IntentEvent(
        clientId: 'a',
        kind: IntentKind.intent,
        source: IntentSource.preset,
        text: 'Check mail',
        declaredAt: now,
        completedAt: now,
      ));
    });

    var finished = false;
    await tester.pumpWidget(MaterialApp(
      home: DayOneStatsScreen(
        openStore: () async => store,
        onFinished: () => finished = true,
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('Your first day'), findsOneWidget);
    expect(find.text('Unlocks'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('Check mail'), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(finished, isTrue);

    await tester.runAsync(() => store.close());
  });
}
