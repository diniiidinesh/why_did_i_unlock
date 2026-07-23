import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:why_did_i_unlock/main.dart';

void main() {
  setUp(() {
    // HomeScreen.initState fires two real plugin calls fire-and-forget:
    // FlutterOverlayWindow.isPermissionGranted() (a MethodChannel call) and
    // AppSettings().promptsEnabled() (SharedPreferencesAsync). Neither has a
    // real platform implementation in a widget test, so both need mocking or
    // they'd throw MissingPluginException from an unawaited Future and fail
    // the test.
    const overlayChannel = MethodChannel('x-slayer/overlay_channel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      overlayChannel,
      (call) async {
        // Return granted=true so _requestOverlayPermission short-circuits
        // without needing to also mock requestPermission().
        if (call.method == 'checkPermission') return true;
        return null;
      },
    );
    // Official in-memory test double for SharedPreferencesAsync (see
    // shared_preferences_platform_interface) — no platform channel involved.
    // Seeded with onboarding already completed so MyApp's AppLauncher (added
    // T12-adjacent, see main.dart) goes straight to HomeScreen instead of
    // OnboardingScreen — that routing decision has its own test below.
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({'onboarding_completed': true});
  });

  testWidgets('13. HomeScreen renders title, prompts toggle, and history entry', (tester) async {
    await tester.pumpWidget(const MyApp());
    // Let AppLauncher's onboardingCompleted() check and HomeScreen
    // initState's mocked-but-still-async calls resolve.
    await tester.pump();
    await tester.pump();

    expect(find.text('Why Did I Unlock?'), findsOneWidget);
    expect(find.text('Unlock prompts'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('View history'), findsOneWidget);
    expect(find.text('Manage options'), findsOneWidget);
    expect(find.text('Status & troubleshooting'), findsOneWidget);
    expect(find.text('About'), findsOneWidget);
  });

  testWidgets('19. AppLauncher shows OnboardingScreen when onboarding is not yet completed', (tester) async {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

    await tester.pumpWidget(const MyApp());
    await tester.pump();
    await tester.pump();

    // OnboardingScreen's first step (value prop) — HomeScreen must NOT be
    // reachable yet.
    expect(find.text('Why Did I Unlock?'), findsNothing);
    expect(find.text('Unlock prompts'), findsNothing);
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
