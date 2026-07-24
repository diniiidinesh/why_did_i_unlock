import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:why_did_i_unlock/home_screen.dart';
import 'package:why_did_i_unlock/insights/outcome_donut.dart';
import 'package:why_did_i_unlock/intent_store.dart';

IntentEvent _event({
  required String clientId,
  IntentKind kind = IntentKind.intent,
  IntentSource? source = IntentSource.preset,
  String text = 'Payments',
  required DateTime at,
  Duration openFor = const Duration(seconds: 30),
}) {
  return IntentEvent(
    clientId: clientId,
    kind: kind,
    source: source,
    text: text,
    declaredAt: at,
    completedAt: at.add(openFor),
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  Future<IntentStore> openStore(WidgetTester tester) async {
    late IntentStore store;
    await tester.runAsync(() async {
      store = await IntentStore.open(path: inMemoryDatabasePath);
    });
    return store;
  }

  Future<void> pumpHome(WidgetTester tester, IntentStore store) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        openStore: () async => store,
        checkPermission: () async => true,
      ),
    ));
    // Real-isolate sqflite work inside HomeScreen._load — see history_screen_test.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      final hasStatus = find.textContaining('Overlay permission').evaluate().isNotEmpty;
      final hasEmpty = find.textContaining('No unlocks yet').evaluate().isNotEmpty;
      final hasCounts = find.textContaining('prompts').evaluate().isNotEmpty;
      if (hasStatus && (hasEmpty || hasCounts)) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('empty install shows first-run copy and nav links', (tester) async {
    final store = await openStore(tester);
    await pumpHome(tester, store);

    expect(find.text('Beacon'), findsOneWidget);
    expect(find.textContaining('No unlocks yet'), findsOneWidget);
    expect(find.text('Settings'), findsWidgets);
    await tester.scrollUntilVisible(find.text('About'), 200);
    expect(find.text('View history'), findsOneWidget);
    expect(find.text('Manage options'), findsOneWidget);
    expect(find.text('Status & troubleshooting'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
    expect(find.byType(OutcomeDonut), findsNothing);

    await tester.runAsync(() => store.close());
  });

  testWidgets('seeded data shows counts, donut categories, and duration stats', (tester) async {
    final store = await openStore(tester);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await store.insertUnlock(unlockedAt: now, promptShown: true);
      await store.insertUnlock(
        unlockedAt: now.subtract(const Duration(minutes: 5)),
        promptShown: false,
        skipReason: SkipReason.cooldown,
      );
      await store.insertEvent(_event(clientId: 'done', at: now));
      await store.insertEvent(_event(
        clientId: 'ni',
        kind: IntentKind.noIntent,
        source: null,
        text: 'Just Like That',
        at: now,
      ));
      await store.insertOpenIntent(_event(clientId: 'open', at: now, openFor: Duration.zero));
      await store.sweepOpenToAbandoned();
    });

    await pumpHome(tester, store);

    expect(find.textContaining('2 unlocks · 1 prompts'), findsOneWidget);
    expect(find.byType(OutcomeDonut), findsOneWidget);
    expect(find.textContaining('Done'), findsWidgets);
    expect(find.textContaining('Abandoned'), findsWidgets);
    expect(find.textContaining('No intent'), findsWidgets);
    await tester.scrollUntilVisible(find.textContaining('Median'), 200);
    expect(find.textContaining('Median'), findsOneWidget);
    expect(find.textContaining('Not enough data yet'), findsNothing);

    await tester.runAsync(() => store.close());
  });

  testWidgets('null duration stats show empty copy when no completed intents exist', (tester) async {
    final store = await openStore(tester);
    final now = DateTime.now();
    await tester.runAsync(() async {
      await store.insertUnlock(unlockedAt: now, promptShown: true);
      await store.insertOpenIntent(_event(clientId: 'still-open', at: now, openFor: Duration.zero));
    });

    await pumpHome(tester, store);

    await tester.scrollUntilVisible(find.text('Not enough data yet'), 200);
    expect(find.text('Not enough data yet'), findsOneWidget);

    await tester.runAsync(() => store.close());
  });

  testWidgets('app resume re-fetches insights written while Home stayed mounted', (tester) async {
    final store = await openStore(tester);
    await pumpHome(tester, store);

    expect(find.textContaining('No unlocks yet'), findsOneWidget);

    final now = DateTime.now();
    await tester.runAsync(() async {
      await store.insertUnlock(unlockedAt: now, promptShown: true);
      await store.insertEvent(_event(clientId: 'after', at: now));
    });

    // Same State is still alive — without resume refresh this would stay empty
    // until kill/reopen (docs/ARCHITECTURE.md §8.1).
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      if (find.textContaining('prompts').evaluate().isNotEmpty) break;
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }

    expect(find.textContaining('1 unlocks · 1 prompts'), findsOneWidget);
    expect(find.byType(OutcomeDonut), findsOneWidget);

    await tester.runAsync(() => store.close());
  });
}
