import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/brand.dart';
import 'package:why_did_i_unlock/oem_autostart_copy.dart';
import 'package:why_did_i_unlock/onboarding_screen.dart';
import 'package:why_did_i_unlock/walkthrough.dart';

void main() {
  Future<void> pumpOnboarding(
    WidgetTester tester, {
    Future<bool> Function()? checkPermission,
    Future<bool?> Function()? requestPermission,
    Future<bool> Function()? checkBatteryExemption,
    Future<void> Function()? requestBatteryExemption,
    Future<String?> Function()? readManufacturer,
    Future<void> Function()? completeOnboarding,
    Future<void> Function(bool enabled)? persistDayOneReminder,
    Future<void> Function()? requestNotificationPermission,
    VoidCallback? onFinished,
    void Function({required int screenWidth, required int screenHeight})? onShowPromptNow,
  }) {
    return tester.pumpWidget(MaterialApp(
      home: OnboardingScreen(
        checkPermission: checkPermission ?? () async => false,
        requestPermission: requestPermission ?? () async => true,
        checkBatteryExemption: checkBatteryExemption ?? () async => false,
        requestBatteryExemption: requestBatteryExemption ?? () async {},
        readManufacturer: readManufacturer ?? () async => null,
        completeOnboarding: completeOnboarding ?? () async {},
        persistDayOneReminder: persistDayOneReminder ?? (_) async {},
        requestNotificationPermission: requestNotificationPermission ?? () async {},
        onFinished: onFinished,
        onShowPromptNow: onShowPromptNow,
      ),
    ));
  }

  Future<void> advanceTo(WidgetTester tester, OnboardingStep step) async {
    for (var i = 0; i < step.index; i++) {
      if (find.text('Continue').evaluate().isEmpty) {
        await tester.tap(find.text('Skip'));
        await tester.pump();
        await tester.pump(); // post-frame onPlaybackActive unhides Continue
      }
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
  }

  int pageCount(WidgetTester tester) {
    final pageView = tester.widget<PageView>(find.byKey(const ValueKey('onboarding-pages')));
    return (pageView.childrenDelegate as SliverChildListDelegate).children.length;
  }

  test('OnboardingStep order is value-prop through try-it', () {
    expect(OnboardingStep.values, [
      OnboardingStep.valueProp,
      OnboardingStep.walkthrough,
      OnboardingStep.permission,
      OnboardingStep.oem,
      OnboardingStep.yourData,
      OnboardingStep.tryIt,
    ]);
  });

  testWidgets('PageView omits Try it now when overlay permission is not granted', (tester) async {
    await pumpOnboarding(tester);
    await tester.pump();

    expect(pageCount(tester), 5);
    expect(find.text('Try it once.'), findsNothing);
  });

  testWidgets('starts on the value-prop step with no Back button', (tester) async {
    await pumpOnboarding(tester);
    await tester.pump();

    expect(find.text('Notice why you picked up your phone'), findsOneWidget);
    expect(find.text('Most unlocks are autopilot. $appDisplayName makes them deliberate.'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Continue advances through every named step in enum order, and Back returns', (tester) async {
    await pumpOnboarding(tester);
    await tester.pump();

    Future<void> tapContinue() async {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    expect(find.text('Notice why you picked up your phone'), findsOneWidget);

    await tapContinue();
    expect(find.text('You unlock.'), findsOneWidget);
    expect(find.text('Skip'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-wizard-chrome')), findsNothing);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Continue'), findsOneWidget);

    await tapContinue();
    expect(find.text('One permission.'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);

    await tapContinue();
    expect(find.text('Keep $appDisplayName awake.'), findsOneWidget);

    await tapContinue();
    expect(find.text('Stays on your phone.'), findsOneWidget);
    expect(find.text('No account. No analytics. No internet.'), findsOneWidget);
    // Final step's primary button reads "Get started", not "Continue".
    expect(find.text('Get started'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Keep $appDisplayName awake.'), findsOneWidget);
  });

  testWidgets('Skip on the walkthrough step jumps to the last beat, not the next onboarding page', (tester) async {
    await pumpOnboarding(tester);
    await tester.pump();
    await advanceTo(tester, OnboardingStep.walkthrough);

    expect(find.text('You unlock.'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    final playing = tester.widget<PageView>(find.byKey(const ValueKey('onboarding-pages')));
    expect(playing.physics, isA<NeverScrollableScrollPhysics>());

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();

    expect(find.text(WalkthroughBeat.values.last.caption), findsOneWidget);
    expect(find.text('One permission.'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
    final holding = tester.widget<PageView>(find.byKey(const ValueKey('onboarding-pages')));
    expect(holding.physics, isNot(isA<NeverScrollableScrollPhysics>()));
  });

  testWidgets('permission step hides the find-hint until "Can\'t find it?" is expanded', (tester) async {
    await pumpOnboarding(tester, checkPermission: () async => true);
    await tester.pump();
    await advanceTo(tester, OnboardingStep.permission);

    expect(find.text('One permission.'), findsOneWidget);
    expect(find.text('The bubble floats over other apps. Android needs your OK.'), findsOneWidget);
    expect(find.text('Can\'t find it?'), findsOneWidget);
    expect(find.textContaining(overlayPermissionFindHint), findsNothing);

    await tester.tap(find.text('Can\'t find it?'));
    await tester.pumpAndSettle();

    expect(find.textContaining(overlayPermissionFindHint), findsOneWidget);
    expect(
      find.text('You can skip and grant this later in Status & troubleshooting.'),
      findsOneWidget,
    );
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
    await advanceTo(tester, OnboardingStep.permission);

    expect(find.text('Grant permission'), findsOneWidget);
    await tester.tap(find.text('Grant permission'));
    await tester.pump();
    await tester.pump();

    expect(requestCalls, 1);
    expect(find.textContaining('Granted'), findsOneWidget);
    // Stay on the permission step — auto-advance after grant was confusing.
    expect(find.text('One permission.'), findsOneWidget);
    expect(find.text('Keep $appDisplayName awake.'), findsNothing);
  });

  testWidgets('resuming on the named permission step re-checks permission status', (tester) async {
    var granted = false;
    await pumpOnboarding(tester, checkPermission: () async => granted);
    await tester.pump();
    await advanceTo(tester, OnboardingStep.permission);

    expect(find.text('One permission.'), findsOneWidget);
    expect(find.textContaining('Not granted'), findsOneWidget);

    granted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Granted'), findsOneWidget);
    expect(find.text('One permission.'), findsOneWidget);
    expect(find.text('Keep $appDisplayName awake.'), findsNothing);
  });

  testWidgets('resuming on a DIFFERENT named step does not trigger a permission re-check', (tester) async {
    var checkCalls = 0;
    await pumpOnboarding(tester, checkPermission: () async {
      checkCalls++;
      return false;
    });
    await tester.pump();
    final callsAfterInitialLoad = checkCalls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(checkCalls, callsAfterInitialLoad);
  });

  testWidgets('resuming on the named OEM step re-checks battery exemption, not permission', (tester) async {
    var permissionChecks = 0;
    var batteryChecks = 0;
    var batteryExempt = false;
    await pumpOnboarding(
      tester,
      checkPermission: () async {
        permissionChecks++;
        return false;
      },
      checkBatteryExemption: () async {
        batteryChecks++;
        return batteryExempt;
      },
    );
    await tester.pump();
    await advanceTo(tester, OnboardingStep.oem);

    expect(find.text('Keep $appDisplayName awake.'), findsOneWidget);
    expect(find.textContaining('Not exempt'), findsOneWidget);

    final permissionChecksOnOem = permissionChecks;
    final batteryChecksOnOem = batteryChecks;
    expect(batteryChecksOnOem, greaterThan(0));

    batteryExempt = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(permissionChecks, permissionChecksOnOem);
    expect(batteryChecks, batteryChecksOnOem + 1);
    expect(find.textContaining('Exempt'), findsOneWidget);
    expect(find.text('Keep $appDisplayName awake.'), findsOneWidget);
  });

  testWidgets('resuming on the named permission step does not re-check battery exemption', (tester) async {
    var batteryChecks = 0;
    await pumpOnboarding(
      tester,
      checkBatteryExemption: () async {
        batteryChecks++;
        return false;
      },
    );
    await tester.pump();
    await advanceTo(tester, OnboardingStep.permission);

    expect(batteryChecks, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(batteryChecks, 0);
    expect(find.text('One permission.'), findsOneWidget);
  });

  testWidgets('continuing without granting permission is not blocked', (tester) async {
    await pumpOnboarding(tester, checkPermission: () async => false);
    await tester.pump();
    await advanceTo(tester, OnboardingStep.permission);

    expect(find.text('One permission.'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Keep $appDisplayName awake.'), findsOneWidget);
  });

  testWidgets('OEM step shows matched Vivo steps when manufacturer is vivo', (tester) async {
    await pumpOnboarding(tester, readManufacturer: () async => 'vivo');
    await tester.pump();
    await advanceTo(tester, OnboardingStep.oem);

    expect(find.text('Keep $appDisplayName awake.'), findsOneWidget);
    expect(find.textContaining('Looks like your phone'), findsOneWidget);
    expect(find.textContaining('Vivo'), findsOneWidget);
    expect(find.textContaining('Background power control'), findsOneWidget);
    expect(find.textContaining('Allow background power usage'), findsOneWidget);
    expect(find.text('My phone isn\'t listed?'), findsNothing);
  });

  testWidgets('OEM step shows generic fallback when manufacturer is unknown', (tester) async {
    await pumpOnboarding(tester, readManufacturer: () async => 'Nothing');
    await tester.pump();
    await advanceTo(tester, OnboardingStep.oem);

    expect(find.textContaining('Battery optimization'), findsOneWidget);
    expect(find.textContaining('Status & troubleshooting'), findsNothing);
  });

  testWidgets('OEM step hides oemGuidanceIntro until "Why does this happen?" is expanded', (tester) async {
    await pumpOnboarding(tester);
    await tester.pump();
    await advanceTo(tester, OnboardingStep.oem);

    expect(find.text('Why does this happen?'), findsOneWidget);
    expect(find.textContaining(oemGuidanceIntro), findsNothing);

    await tester.ensureVisible(find.text('Why does this happen?'));
    await tester.tap(find.text('Why does this happen?'));
    await tester.pumpAndSettle();

    expect(find.textContaining(oemGuidanceIntro), findsOneWidget);
  });

  testWidgets('"Get started" on the last named step marks onboarding complete and calls onFinished', (tester) async {
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

    await advanceTo(tester, OnboardingStep.yourData);

    expect(find.text('Get started'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump();

    expect(completed, isTrue);
    expect(finished, isTrue);
  });

  testWidgets('last-step reminder defaults on; Get started requests notification permission', (tester) async {
    bool? persisted;
    var requested = 0;
    await pumpOnboarding(
      tester,
      persistDayOneReminder: (enabled) async => persisted = enabled,
      requestNotificationPermission: () async { requested++; },
    );
    await tester.pump();
    await advanceTo(tester, OnboardingStep.yourData);

    expect(find.text('Remind me tomorrow to check my first day'), findsOneWidget);
    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump();

    expect(persisted, isTrue);
    expect(requested, 1);
  });

  testWidgets('turning the reminder off skips the permission request', (tester) async {
    bool? persisted;
    var requested = 0;
    await pumpOnboarding(
      tester,
      persistDayOneReminder: (enabled) async => persisted = enabled,
      requestNotificationPermission: () async { requested++; },
    );
    await tester.pump();
    await advanceTo(tester, OnboardingStep.yourData);

    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Get started'));
    await tester.pump();
    await tester.pump();

    expect(persisted, isFalse);
    expect(requested, 0);
  });

  testWidgets('Try it now appears only with overlay permission and can skip', (tester) async {
    var finished = false;
    var shown = 0;
    await pumpOnboarding(
      tester,
      checkPermission: () async => true,
      onFinished: () => finished = true,
      onShowPromptNow: ({required screenWidth, required screenHeight}) {
        shown++;
      },
    );
    await tester.pump();
    await tester.pump();

    expect(pageCount(tester), 6);
    await advanceTo(tester, OnboardingStep.tryIt);
    expect(find.text('Try it once.'), findsOneWidget);
    expect(find.text('See the prompt and bubble for real. Nothing is saved.'), findsOneWidget);
    expect(find.text('Get started'), findsNothing);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump();
    expect(finished, isTrue);
    expect(shown, 0);
  });

  testWidgets('Try it now Show me fires the practice prompt then finishes', (tester) async {
    var finished = false;
    var shown = 0;
    await pumpOnboarding(
      tester,
      checkPermission: () async => true,
      onFinished: () => finished = true,
      onShowPromptNow: ({required screenWidth, required screenHeight}) {
        shown++;
      },
    );
    await tester.pump();
    await tester.pump();

    await advanceTo(tester, OnboardingStep.tryIt);
    await tester.tap(find.text('Show me'));
    await tester.pump();
    await tester.pump();
    expect(shown, 1);
    expect(finished, isTrue);
  });
}
