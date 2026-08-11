import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:why_did_i_unlock/home_screen.dart';
import 'package:why_did_i_unlock/intent_store.dart';
import 'package:why_did_i_unlock/main.dart';

void main() {
  setUp(() {
    // HomeScreen.initState fires plugin calls: overlay permission check and
    // (unless injected) IntentStore.open. Widget tests that pump HomeScreen
    // directly inject openStore; the MyApp path below mocks the overlay
    // channel and relies on HomeScreen catching a failed real DB open.
    const overlayChannel = MethodChannel('x-slayer/overlay_channel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      overlayChannel,
      (call) async {
        if (call.method == 'checkPermission') return true;
        return null;
      },
    );
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'onboarding_completed': true});
  });

  testWidgets('13. HomeScreen renders title and every nav entry', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    late IntentStore store;
    await tester.runAsync(() async {
      store = await IntentStore.open(path: inMemoryDatabasePath);
    });

    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        openStore: () async => store,
        checkPermission: () async => true,
        checkBatteryExemption: () async => true,
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pump();

    expect(find.text('Beacon'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Settings'), findsWidgets);
    await tester.scrollUntilVisible(find.text('About'), 200);
    expect(find.text('View history'), findsOneWidget);
    expect(find.text('Manage options'), findsOneWidget);
    expect(find.text('Status & troubleshooting'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);

    await tester.runAsync(() => store.close());
  });

  testWidgets('19. AppLauncher shows OnboardingScreen when onboarding is not yet completed', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.pump();

    // OnboardingScreen's first step (value prop) — HomeScreen must NOT be
    // reachable yet.
    expect(find.text('Beacon'), findsNothing);
    expect(find.text('Settings'), findsNothing);
  });

  testWidgets(
    '14. IntentCaptureScreen renders presets, Just Like That, text field and OK',
    (tester) async {
      // Presets are DB-backed and injected via the constructor since T11
      // (config relay) — no longer a hardcoded global the widget reads
      // itself, so the test supplies its own sample set.
      const samplePresets = [
        CapturePreset(id: 1, label: 'Payments'),
        CapturePreset(id: 2, label: 'Calls'),
        CapturePreset(id: 3, label: 'Messages'),
      ];
      await tester.pumpWidget(const MaterialApp(
        home: IntentCaptureScreen(
          presets: samplePresets,
          onSubmit: _noopOnSubmit,
          onNoIntent: _noopOnNoIntent,
        ),
      ));

      for (final preset in samplePresets) {
        expect(find.text(preset.label), findsOneWidget);
      }
      expect(find.text(noIntentLabel), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    },
  );

  testWidgets(
    '16. IntentCaptureScreen renders correctly with an empty preset list',
    (tester) async {
      // A deliberately valid state (docs/DATA_MODEL.md §7) — the very first
      // capture screen after an overlay engine cold start, before the
      // config-relay reply has arrived, looks exactly like this.
      await tester.pumpWidget(const MaterialApp(
        home: IntentCaptureScreen(
          presets: [],
          onSubmit: _noopOnSubmit,
          onNoIntent: _noopOnNoIntent,
        ),
      ));

      expect(find.text(noIntentLabel), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    },
  );

  testWidgets(
    '17. IntentCaptureScreen passes the tapped preset\'s id back through onSubmit',
    (tester) async {
      String? capturedText;
      String? capturedSource;
      int? capturedPresetId;

      await tester.pumpWidget(MaterialApp(
        home: IntentCaptureScreen(
          presets: const [CapturePreset(id: 42, label: 'Payments')],
          onSubmit: (text, source, {presetId}) {
            capturedText = text;
            capturedSource = source;
            capturedPresetId = presetId;
          },
          onNoIntent: _noopOnNoIntent,
        ),
      ));

      await tester.tap(find.text('Payments'));
      await tester.pump();

      expect(capturedText, 'Payments');
      expect(capturedSource, 'preset');
      expect(capturedPresetId, 42);
    },
  );

  testWidgets(
    '18. Custom text submission carries no presetId',
    (tester) async {
      int? capturedPresetId = -1; // sentinel distinct from both null and any real id
      await tester.pumpWidget(MaterialApp(
        home: IntentCaptureScreen(
          presets: const [],
          onSubmit: (text, source, {presetId}) => capturedPresetId = presetId,
          onNoIntent: _noopOnNoIntent,
        ),
      ));

      await tester.enterText(find.byType(TextField), 'Groceries');
      await tester.tap(find.text('OK'));
      await tester.pump();

      expect(capturedPresetId, isNull);
    },
  );
}

void _noopOnSubmit(String text, String source, {int? presetId}) {}
void _noopOnNoIntent() {}
