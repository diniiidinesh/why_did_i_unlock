import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:why_did_i_unlock/about_screen.dart' show privacyPolicyUrl;
import 'package:why_did_i_unlock/app_settings.dart';
import 'package:why_did_i_unlock/intent_store.dart';
import 'package:why_did_i_unlock/settings_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppSettings settings;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    settings = const AppSettings();
  });

  Future<IntentStore> openStore(WidgetTester tester) async {
    late IntentStore store;
    await tester.runAsync(() async {
      store = await IntentStore.open(path: inMemoryDatabasePath);
    });
    return store;
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required IntentStore store,
    Future<bool> Function(Uri uri)? launch,
    WidgetBuilder? managePresetsBuilder,
    Future<void> Function()? exportAndShare,
  }) async {
    // Your data sits below cooldown/probability/quiet hours — a short
    // surface leaves Export/retention/delete off-screen even after
    // scrollUntilVisible's "found in tree" check (hit-test Y > 600).
    final view = tester.view;
    view.physicalSize = const Size(800, 1600);
    view.devicePixelRatio = 1.0;
    addTearDown(view.resetPhysicalSize);
    addTearDown(view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        settings: settings,
        launch: launch ?? (_) async => true,
        managePresetsBuilder: managePresetsBuilder ?? (_) => const Scaffold(body: Text('Manage options stub')),
        exportAndShare: exportAndShare,
        openStore: () async => store,
      ),
    ));
    // YourDataCard loads via real-isolate sqflite — same pattern as history_screen_test.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pump();
    for (var i = 0; i < 20 && find.text('Events stored').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
  }

  testWidgets('prompts switch round-trips through AppSettings', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    expect(await settings.promptsEnabled(), isTrue); // default
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pump();

    expect(await settings.promptsEnabled(), isFalse);
    await tester.runAsync(() => store.close());
  });

  testWidgets('tapping a cooldown preset chip writes that value', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    await tester.tap(find.widgetWithText(ChoiceChip, '5 min'));
    await tester.pump();

    expect(await settings.cooldownMinutes(), 5);
    await tester.runAsync(() => store.close());
  });

  testWidgets('tapping a probability preset chip writes that value as a 0.0-1.0 fraction', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    await tester.tap(find.widgetWithText(ChoiceChip, '75%'));
    await tester.pump();

    expect(await settings.promptProbability(), 0.75);
    await tester.runAsync(() => store.close());
  });

  testWidgets('custom cooldown in-range value is stored as typed', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom').first);
    await tester.pump();

    final cooldownField = find.byType(TextField).first;
    await tester.enterText(cooldownField, '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(await settings.cooldownMinutes(), 7);
    expect(find.byType(SnackBar), findsNothing);
    await tester.runAsync(() => store.close());
  });

  testWidgets('a previously-stored non-preset cooldown value shows Custom selected and prefilled', (tester) async {
    await settings.setCooldownMinutes(7);
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    final customChip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Custom').first);
    expect(customChip.selected, isTrue);
    expect(find.text('7'), findsOneWidget);
    await tester.runAsync(() => store.close());
  });

  testWidgets('typing an out-of-range custom cooldown shows a SnackBar and clamps to the max', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom').first);
    await tester.pump();

    final cooldownField = find.byType(TextField).first;
    await tester.enterText(cooldownField, '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.textContaining('0–30 minutes'), findsOneWidget);
    expect(await settings.cooldownMinutes(), AppSettings.cooldownMaxMinutes);
    await tester.runAsync(() => store.close());
  });

  testWidgets('typing an out-of-range custom probability shows a SnackBar and clamps to the min', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom').last);
    await tester.pump();

    final probabilityField = find.byType(TextField).last;
    await tester.enterText(probabilityField, '10');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.textContaining('25–100%'), findsOneWidget);
    expect(await settings.promptProbability(), AppSettings.probabilityMin);
    await tester.runAsync(() => store.close());
  });

  testWidgets('typing a non-numeric custom value shows a SnackBar and does not change stored value', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    final before = await settings.cooldownMinutes();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom').first);
    await tester.pump();

    final cooldownField = find.byType(TextField).first;
    await tester.enterText(cooldownField, 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Enter a whole number of minutes.'), findsOneWidget);
    expect(await settings.cooldownMinutes(), before);
    await tester.runAsync(() => store.close());
  });

  testWidgets('quiet hours switch round-trips through AppSettings', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    expect(await settings.quietHoursEnabled(), isFalse); // default
    await tester.tap(find.byType(SwitchListTile).last);
    await tester.pump();

    expect(await settings.quietHoursEnabled(), isTrue);
    await tester.runAsync(() => store.close());
  });

  testWidgets('quiet hours start/end times render as HH:mm from the stored window', (tester) async {
    await settings.setQuietHoursWindow(const QuietHoursWindow(startMinutes: 23 * 60, endMinutes: 6 * 60 + 30));
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('06:30'), findsOneWidget);
    await tester.runAsync(() => store.close());
  });

  testWidgets('tapping "Manage options" pushes the injected builder', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    await tester.scrollUntilVisible(find.text('Manage options'), 200);
    await tester.tap(find.text('Manage options'));
    await tester.pumpAndSettle();

    expect(find.text('Manage options stub'), findsOneWidget);
    await tester.runAsync(() => store.close());
  });

  testWidgets('tapping "Privacy policy" launches the published policy URL', (tester) async {
    Uri? launched;
    final store = await openStore(tester);
    await pumpScreen(tester, store: store, launch: (uri) async {
      launched = uri;
      return true;
    });

    await tester.scrollUntilVisible(find.text('Privacy policy'), 200);
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();

    expect(launched, Uri.parse(privacyPolicyUrl));
    expect(find.byType(SnackBar), findsNothing);
    await tester.runAsync(() => store.close());
  });

  testWidgets('a privacy policy launch failure shows a SnackBar', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store, launch: (_) async => false);

    await tester.scrollUntilVisible(find.text('Privacy policy'), 200);
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();

    expect(find.text('Privacy policy isn\'t published yet.'), findsOneWidget);
    await tester.runAsync(() => store.close());
  });

  testWidgets('tapping "Export data" invokes the injected exporter', (tester) async {
    var exportCalls = 0;
    final store = await openStore(tester);
    await pumpScreen(tester, store: store, exportAndShare: () async {
      exportCalls++;
    });

    await tester.scrollUntilVisible(find.text('Export data'), 200);
    await tester.ensureVisible(find.text('Export data'));
    await tester.pump();
    await tester.tap(find.text('Export data'));
    await tester.pump();

    expect(exportCalls, 1);
    expect(find.byType(SnackBar), findsNothing);
    await tester.runAsync(() => store.close());
  });

  testWidgets('an export failure shows a SnackBar', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store, exportAndShare: () async {
      throw Exception('share failed');
    });

    await tester.scrollUntilVisible(find.text('Export data'), 200);
    await tester.ensureVisible(find.text('Export data'));
    await tester.pump();
    await tester.tap(find.text('Export data'));
    await tester.pump();

    expect(find.text('Export failed. Please try again.'), findsOneWidget);
    await tester.runAsync(() => store.close());
  });

  testWidgets('retention chip round-trips through AppSettings', (tester) async {
    final store = await openStore(tester);
    await pumpScreen(tester, store: store);

    await tester.scrollUntilVisible(find.text('Forever'), 200);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Forever'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Forever'));
    await tester.pump();

    expect(await settings.retentionPeriod(), RetentionPeriod.forever);
    await tester.runAsync(() => store.close());
  });

  testWidgets('delete all confirms and clears unlock/intent rows, keeps presets', (tester) async {
    final store = await openStore(tester);
    await tester.runAsync(() async {
      await store.insertUnlock(unlockedAt: DateTime.utc(2026, 7, 1), promptShown: true);
    });
    await pumpScreen(tester, store: store);

    await tester.scrollUntilVisible(find.text('Delete all event history'), 200);
    await tester.ensureVisible(find.text('Delete all event history'));
    await tester.pump();
    await tester.tap(find.text('Delete all event history'));
    await tester.pumpAndSettle();

    expect(find.text('Delete all event history?'), findsOneWidget);
    await tester.tap(find.text('Delete all'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    late UserDataCounts counts;
    late List<IntentPreset> presets;
    await tester.runAsync(() async {
      counts = await store.userDataCounts();
      presets = await store.activePresets();
    });
    expect(counts.unlockCount, 0);
    expect(counts.intentCount, 0);
    expect(presets, isNotEmpty);
    await tester.runAsync(() => store.close());
  });
}
