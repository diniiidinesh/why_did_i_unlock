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
    // _shouldPrompt() (SharedPreferencesAsync). Neither has a real platform
    // implementation in a widget test, so both need mocking or they'd throw
    // MissingPluginException from an unawaited Future and fail the test.
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
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('13. HomeScreen renders title, prompts toggle, and history entry', (tester) async {
    await tester.pumpWidget(const MyApp());
    // Let initState's mocked-but-still-async calls resolve.
    await tester.pump();
    await tester.pump();

    expect(find.text('Why Did I Unlock?'), findsOneWidget);
    expect(find.text('Unlock prompts'), findsOneWidget);
    expect(find.byType(Switch), findsOneWidget);
    expect(find.text('View history'), findsOneWidget);
  });

  testWidgets(
    '14. IntentCaptureScreen renders presets, Just Like That, text field and OK',
    (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: IntentCaptureScreen(
          onSubmit: (_, _) {},
          onNoIntent: () {},
        ),
      ));

      for (final preset in intentPresets) {
        expect(find.text(preset), findsOneWidget);
      }
      expect(find.text(noIntentLabel), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    },
  );
}
