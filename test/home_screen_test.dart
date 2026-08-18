import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:why_did_i_unlock/home_screen.dart';
import 'package:why_did_i_unlock/app_settings.dart';
import 'package:why_did_i_unlock/discovery_tooltip.dart';
import 'package:why_did_i_unlock/insights/outcome_donut.dart';
import 'package:why_did_i_unlock/intent_store.dart';
import 'package:why_did_i_unlock/nudge_tuning.dart';

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
    // Existing Home tests are not about coach marks — keep those isolated.
    DiscoverySession.skipThisLaunch = true;
  });

  Future<IntentStore> openStore(WidgetTester tester) async {
    late IntentStore store;
    await tester.runAsync(() async {
      store = await IntentStore.open(path: inMemoryDatabasePath, ownConnection: true);
    });
    return store;
  }

  Future<void> pumpHome(
    WidgetTester tester,
    IntentStore store, {
    Future<bool> Function()? checkBatteryExemption,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        openStore: () async => store,
        checkPermission: () async => true,
        checkBatteryExemption: checkBatteryExemption ?? () async => true,
      ),
    ));
    // Real-isolate sqflite work inside HomeScreen._load — see history_screen_test.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      final hasStatus = find.textContaining('Overlay permission').evaluate().isNotEmpty ||
          find.textContaining('overlay permission').evaluate().isNotEmpty;
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
    expect(find.text('How long until Done'), findsOneWidget);
    expect(find.textContaining('Median'), findsOneWidget);
    expect(find.textContaining('Mean'), findsOneWidget);
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

  testWidgets('shows OEM nudge when battery not exempt; dismiss hides it', (tester) async {
    final store = await openStore(tester);
    await const AppSettings().setWalkthroughSeenVersion(AppSettings.currentWalkthroughVersion);
    await pumpHome(tester, store, checkBatteryExemption: () async => false);

    expect(find.text('Keep monitoring alive'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Keep monitoring alive'), findsNothing);

    await tester.runAsync(() => store.close());
  });

  testWidgets('hides OEM nudge when battery already exempt', (tester) async {
    final store = await openStore(tester);
    await pumpHome(tester, store, checkBatteryExemption: () async => true);

    expect(find.text('Keep monitoring alive'), findsNothing);

    await tester.runAsync(() => store.close());
  });

  testWidgets('existing install with unseen walkthrough shows the re-entry card; dismiss hides it', (tester) async {
    final store = await openStore(tester);
    await pumpHome(tester, store);

    expect(find.text('See how Beacon works'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    await tester.pump();
    expect(find.text('See how Beacon works'), findsNothing);

    await tester.runAsync(() => store.close());
  });

  testWidgets('hides the walkthrough re-entry card once the current version has been seen', (tester) async {
    final store = await openStore(tester);
    await const AppSettings().setWalkthroughSeenVersion(AppSettings.currentWalkthroughVersion);
    await pumpHome(tester, store);

    expect(find.text('See how Beacon works'), findsNothing);

    await tester.runAsync(() => store.close());
  });

  testWidgets('after the first unlock, Settings tooltip shows; Got it queues Manage', (tester) async {
    DiscoverySession.skipThisLaunch = false;
    final view = tester.view;
    view.physicalSize = const Size(800, 2400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    final store = await openStore(tester);
    await tester.runAsync(() async {
      await store.insertUnlock(unlockedAt: DateTime.now(), promptShown: true);
    });
    await const AppSettings().setWalkthroughSeenVersion(AppSettings.currentWalkthroughVersion);
    await pumpHome(tester, store);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('discovery-tooltip-manage')), findsNothing);

    await tester.tap(find.text(DiscoveryCopy.gotIt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsNothing);
    expect(find.byKey(const ValueKey('discovery-tooltip-manage')), findsOneWidget);

    await tester.runAsync(() => store.close());
  });

  testWidgets('scrolling Home does not dismiss Settings or duplicate Manage', (tester) async {
    DiscoverySession.skipThisLaunch = false;
    final view = tester.view;
    view.physicalSize = const Size(800, 2400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    final store = await openStore(tester);
    await tester.runAsync(() async {
      await store.insertUnlock(unlockedAt: DateTime.now(), promptShown: true);
    });
    await const AppSettings().setWalkthroughSeenVersion(AppSettings.currentWalkthroughVersion);
    await pumpHome(tester, store);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('discovery-tooltip-manage')), findsNothing);

    await tester.tap(find.text(DiscoveryCopy.gotIt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsNothing);
    expect(find.byKey(const ValueKey('discovery-tooltip-manage')), findsOneWidget);

    await tester.tap(find.text(DiscoveryCopy.gotIt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byKey(const ValueKey('discovery-tooltip-manage')), findsNothing);
    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsNothing);

    await tester.runAsync(() => store.close());
  });

  testWidgets('opening Settings retires that tooltip', (tester) async {
    DiscoverySession.skipThisLaunch = false;
    final view = tester.view;
    view.physicalSize = const Size(800, 2400);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    final store = await openStore(tester);
    await tester.runAsync(() async {
      await store.insertUnlock(unlockedAt: DateTime.now(), promptShown: true);
    });
    await const AppSettings().setWalkthroughSeenVersion(AppSettings.currentWalkthroughVersion);
    await const AppSettings().setSettingsScreenOpened(true);
    await pumpHome(tester, store);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsNothing);
    expect(find.byKey(const ValueKey('discovery-tooltip-manage')), findsOneWidget);

    await tester.runAsync(() => store.close());
  });

  testWidgets('fallback banner appears once launches hit the threshold', (tester) async {
    DiscoverySession.skipThisLaunch = false;
    final store = await openStore(tester);
    final settings = const AppSettings();
    await settings.setWalkthroughSeenVersion(AppSettings.currentWalkthroughVersion);
    for (var i = 0; i < NudgeTuning.nudgeBannerLaunchThreshold; i++) {
      await settings.incrementAppLaunchCount();
    }
    await pumpHome(tester, store);
    await tester.pump();

    // Home._load increments once more (this landing). Threshold is already met.
    expect(find.text('A few things you can change'), findsOneWidget);
    expect(find.byKey(const ValueKey('discovery-tooltip-settings')), findsNothing);

    await tester.runAsync(() => store.close());
  });
}
