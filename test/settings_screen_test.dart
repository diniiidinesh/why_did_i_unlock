import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:why_did_i_unlock/about_screen.dart' show privacyPolicyUrl;
import 'package:why_did_i_unlock/app_settings.dart';
import 'package:why_did_i_unlock/settings_screen.dart';

void main() {
  late AppSettings settings;

  setUp(() {
    // Same in-memory test double used by app_settings_test.dart /
    // widget_test.dart — a fresh empty store per test, no real platform
    // channel involved.
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    settings = const AppSettings();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<bool> Function(Uri uri)? launch,
    WidgetBuilder? managePresetsBuilder,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        settings: settings,
        launch: launch ?? (_) async => true,
        managePresetsBuilder: managePresetsBuilder ?? (_) => const Scaffold(body: Text('Manage presets stub')),
      ),
    ));
    // Let the parallel-await load resolve.
    await tester.pump();
    await tester.pump();
  }

  testWidgets('prompts switch round-trips through AppSettings', (tester) async {
    await pumpScreen(tester);

    expect(await settings.promptsEnabled(), isTrue); // default
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pump();

    expect(await settings.promptsEnabled(), isFalse);
  });

  testWidgets('tapping a cooldown preset chip writes that value', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '5 min'));
    await tester.pump();

    expect(await settings.cooldownMinutes(), 5);
  });

  testWidgets('tapping a probability preset chip writes that value as a 0.0-1.0 fraction', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, '75%'));
    await tester.pump();

    expect(await settings.promptProbability(), 0.75);
  });

  testWidgets('custom cooldown in-range value is stored as typed', (tester) async {
    await pumpScreen(tester);

    // Cooldown defaults to 1, which IS a preset — select Custom to reveal
    // the text field.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom').first);
    await tester.pump();

    final cooldownField = find.byType(TextField).first;
    await tester.enterText(cooldownField, '7');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(await settings.cooldownMinutes(), 7);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a previously-stored non-preset cooldown value shows Custom selected and prefilled', (tester) async {
    await settings.setCooldownMinutes(7);
    await pumpScreen(tester);

    final customChip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Custom').first);
    expect(customChip.selected, isTrue);
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('typing an out-of-range custom cooldown shows a SnackBar and clamps to the max', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom').first);
    await tester.pump();

    final cooldownField = find.byType(TextField).first;
    await tester.enterText(cooldownField, '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.textContaining('0–30 minutes'), findsOneWidget);
    expect(await settings.cooldownMinutes(), AppSettings.cooldownMaxMinutes);
  });

  testWidgets('typing an out-of-range custom probability shows a SnackBar and clamps to the min', (tester) async {
    await pumpScreen(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom').last);
    await tester.pump();

    final probabilityField = find.byType(TextField).last;
    await tester.enterText(probabilityField, '10');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.textContaining('25–100%'), findsOneWidget);
    expect(await settings.promptProbability(), AppSettings.probabilityMin);
  });

  testWidgets('typing a non-numeric custom value shows a SnackBar and does not change stored value', (tester) async {
    await pumpScreen(tester);

    final before = await settings.cooldownMinutes();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Custom').first);
    await tester.pump();

    final cooldownField = find.byType(TextField).first;
    await tester.enterText(cooldownField, 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(find.text('Enter a whole number of minutes.'), findsOneWidget);
    expect(await settings.cooldownMinutes(), before);
  });

  testWidgets('quiet hours switch round-trips through AppSettings', (tester) async {
    await pumpScreen(tester);

    expect(await settings.quietHoursEnabled(), isFalse); // default
    await tester.tap(find.byType(SwitchListTile).last);
    await tester.pump();

    expect(await settings.quietHoursEnabled(), isTrue);
  });

  testWidgets('quiet hours start/end times render as HH:mm from the stored window', (tester) async {
    await settings.setQuietHoursWindow(const QuietHoursWindow(startMinutes: 23 * 60, endMinutes: 6 * 60 + 30));
    await pumpScreen(tester);

    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('06:30'), findsOneWidget);
  });

  testWidgets('tapping "Manage presets" pushes the injected builder', (tester) async {
    await pumpScreen(tester);

    // Below the fold — this screen's ListView only builds items within its
    // viewport + cache extent (same reasoning as StatusScreen's own test).
    await tester.scrollUntilVisible(find.text('Manage presets'), 200);
    await tester.tap(find.text('Manage presets'));
    await tester.pumpAndSettle();

    expect(find.text('Manage presets stub'), findsOneWidget);
  });

  testWidgets('tapping "Privacy policy" launches the placeholder URL', (tester) async {
    Uri? launched;
    await pumpScreen(tester, launch: (uri) async {
      launched = uri;
      return true;
    });

    await tester.scrollUntilVisible(find.text('Privacy policy'), 200);
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();

    expect(launched, Uri.parse(privacyPolicyUrl));
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('a privacy policy launch failure shows a SnackBar', (tester) async {
    await pumpScreen(tester, launch: (_) async => false);

    await tester.scrollUntilVisible(find.text('Privacy policy'), 200);
    await tester.tap(find.text('Privacy policy'));
    await tester.pump();

    expect(find.text('Privacy policy isn\'t published yet.'), findsOneWidget);
  });
}
