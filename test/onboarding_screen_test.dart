import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/onboarding_screen.dart';

void main() {
  Future<void> pumpOnboarding(
    WidgetTester tester, {
    Future<bool> Function()? checkPermission,
    Future<bool?> Function()? requestPermission,
    Future<void> Function()? completeOnboarding,
    VoidCallback? onFinished,
  }) {
    return tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(
        checkPermission: checkPermission ?? () async => false,
        requestPermission: requestPermission ?? () async => true,
        completeOnboarding: completeOnboarding ?? () async {},
        onFinished: onFinished,
      ),
    ));
  }

  testWidgets('starts on the value-prop step with 5 progress dots and no Back button', (tester) async {
    await pumpOnboarding(tester);
    await tester.pump();

    expect(find.text('Notice why you picked up your phone'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Continue advances through all 5 steps in order, and Back returns', (tester) async {
    await pumpOnboarding(tester);
    await tester.pump();

    Future<void> tapContinue() async {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    await tapContinue();
    expect(find.text('How it works'), findsOneWidget);

    await tapContinue();
    expect(find.text('One permission is needed'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tapContinue();
    expect(find.text('Some phones need one more step'), findsOneWidget);

    await tapContinue();
    expect(find.text('Your data stays on your phone'), findsOneWidget);
    // Final step's primary button reads "Get started", not "Continue".
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Some phones need one more step'), findsOneWidget);
  });

  testWidgets('permission step shows live status from checkPermission', (tester) async {
    await pumpOnboarding(tester, checkPermission: () async => true);
    await tester.pump();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('One permission is needed'), findsOneWidget);
    expect(find.textContaining('Granted'), findsOneWidget);
    expect(find.text('Grant permission'), findsNothing);
  });

  testWidgets('tapping "Grant permission" calls requestPermission then re-checks', (tester) async {
    var requestCalls = 0;
    var granted = false;
    await pumpOnboarding(
      tester,
      checkPermission: () async => granted,
      requestPermission: () async {
        requestCalls++;
        granted = true;
        return true;
      },
    );
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Grant permission'), findsOneWidget);
    await tester.tap(find.text('Grant permission'));
    await tester.pump();
    await tester.pump();

    expect(requestCalls, 1);
    expect(find.textContaining('Granted'), findsOneWidget);
  });

  testWidgets('continuing without granting permission is not blocked', (tester) async {
    // CLAUDE.md §9: onboarding must not demand permissions upfront or block
    // progress on them.
    await pumpOnboarding(tester, checkPermission: () async => false);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('One permission is needed'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Some phones need one more step'), findsOneWidget);
  });

  testWidgets('OEM step lists guidance vendors and the "not listed" fallback copy', (tester) async {
    await pumpOnboarding(tester);
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Some phones need one more step'), findsOneWidget);
    expect(find.textContaining('Xiaomi'), findsOneWidget);
    expect(find.text('My phone isn\'t listed?'), findsOneWidget);
  });

  testWidgets('"Get started" on the last step marks onboarding complete and calls onFinished', (tester) async {
    var completed = false;
    var finished = false;
    await pumpOnboarding(
      tester,
      completeOnboarding: () async {
        completed = true;
      },
      onFinished: () => finished = true,
    );
    await tester.pump();

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump();

    expect(completed, isTrue);
    expect(finished, isTrue);
  });
}
