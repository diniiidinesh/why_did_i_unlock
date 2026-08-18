import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:why_did_i_unlock/history_screen.dart';
import 'package:why_did_i_unlock/intent_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  testWidgets(
    '15. HistoryScreen renders one row per event, newest first, styles no_intent distinctly',
    (tester) async {
      late IntentStore store;
      // sqflite_common_ffi does its real work on a background Isolate — real
      // async I/O, not a fake-Timer-based Future. testWidgets' default
      // automated test zone can deadlock a setState() triggered by that kind
      // of real callback (confirmed by hanging indefinitely here without
      // this wrapper). tester.runAsync() is Flutter's documented escape
      // hatch: it runs the given callback in the real root zone so genuine
      // async I/O (isolates, real Timers, file I/O) completes normally.
      await tester.runAsync(() async {
        store = await IntentStore.open(path: inMemoryDatabasePath, ownConnection: true);
        await store.insertEvent(IntentEvent(
          clientId: 'a',
          kind: IntentKind.intent,
          source: IntentSource.preset,
          text: 'Payments',
          declaredAt: DateTime.utc(2026, 1, 1, 9, 0, 0),
          completedAt: DateTime.utc(2026, 1, 1, 9, 0, 5),
        ));
        await store.insertEvent(IntentEvent(
          clientId: 'b',
          kind: IntentKind.noIntent,
          source: null,
          text: 'Just Like That',
          declaredAt: DateTime.utc(2026, 1, 1, 10, 0, 0),
          completedAt: DateTime.utc(2026, 1, 1, 10, 0, 0),
        ));
      });

      await tester.pumpWidget(MaterialApp(
        home: HistoryScreen(openStore: () async => store),
      ));
      // HistoryScreen's initState fires _load(), which awaits the store's
      // real-isolate recentEvents() call — again real I/O, so give it the
      // same real-zone treatment before pumping the resulting rebuild.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();

      expect(find.text('Payments'), findsOneWidget);
      expect(find.text('Just Like That'), findsOneWidget);

      // Newest-first: "Just Like That" (10:00) precedes "Payments" (09:00:05).
      final noIntentPos = tester.getTopLeft(find.text('Just Like That')).dy;
      final intentPos = tester.getTopLeft(find.text('Payments')).dy;
      expect(noIntentPos, lessThan(intentPos));

      // Distinct styling: no_intent row is italic, intent row is not.
      final noIntentWidget = tester.widget<Text>(find.text('Just Like That'));
      final intentWidget = tester.widget<Text>(find.text('Payments'));
      expect(noIntentWidget.style?.fontStyle, FontStyle.italic);
      expect(intentWidget.style?.fontStyle, isNot(FontStyle.italic));

      await tester.runAsync(() => store.close());
    },
  );

  testWidgets('HistoryScreen shows empty state with no events', (tester) async {
    late IntentStore store;
    await tester.runAsync(() async {
      store = await IntentStore.open(path: inMemoryDatabasePath, ownConnection: true);
    });

    await tester.pumpWidget(MaterialApp(
      home: HistoryScreen(openStore: () async => store),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();

    expect(find.text('No unlocks logged yet'), findsOneWidget);

    await tester.runAsync(() => store.close());
  });
}
