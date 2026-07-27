import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/oem_autostart_copy.dart';
import 'package:why_did_i_unlock/status_screen.dart';

void main() {
  testWidgets('shows Granted and no grant button when permission is already granted', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StatusScreen(
        checkPermission: () async => true,
        requestPermission: () async => true,
        onShowPromptNow: ({required screenWidth, required screenHeight}) {},
        checkBatteryExemption: () async => true,
        requestBatteryExemption: () async {},
      ),
    ));
    await tester.pump();

    expect(find.text('Granted'), findsOneWidget);
    expect(find.text('Grant permission'), findsNothing);
    // Two "Refresh status" buttons now — one on the overlay-permission card,
    // one on the battery-exemption card added alongside this feature.
    expect(find.text('Refresh status'), findsNWidgets(2));
  });

  testWidgets('shows Not granted and a grant button when permission is missing', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StatusScreen(
        checkPermission: () async => false,
        requestPermission: () async => true,
        onShowPromptNow: ({required screenWidth, required screenHeight}) {},
        checkBatteryExemption: () async => true,
        requestBatteryExemption: () async {},
      ),
    ));
    await tester.pump();

    expect(find.text('Not granted'), findsOneWidget);
    expect(find.text('Grant permission'), findsOneWidget);
  });

  testWidgets('tapping "Grant permission" calls requestPermission then re-checks', (tester) async {
    var requestCalls = 0;
    var granted = false;
    await tester.pumpWidget(MaterialApp(
      home: StatusScreen(
        checkPermission: () async => granted,
        requestPermission: () async {
          requestCalls++;
          granted = true; // Simulate the user granting it in system settings.
          return true;
        },
        onShowPromptNow: ({required screenWidth, required screenHeight}) {},
        checkBatteryExemption: () async => true,
        requestBatteryExemption: () async {},
      ),
    ));
    await tester.pump();
    expect(find.text('Not granted'), findsOneWidget);

    await tester.tap(find.text('Grant permission'));
    await tester.pump();
    await tester.pump();

    expect(requestCalls, 1);
    expect(find.text('Granted'), findsOneWidget);
  });

  testWidgets('lists every OEM guidance vendor plus the "not listed" fallback', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StatusScreen(
        checkPermission: () async => true,
        requestPermission: () async => true,
        onShowPromptNow: ({required screenWidth, required screenHeight}) {},
        checkBatteryExemption: () async => true,
        requestBatteryExemption: () async {},
        readManufacturer: () async => null,
      ),
    ));
    await tester.pump();

    // The battery-exemption card added above the OEM list pushes these below
    // the ListView's initial viewport + cache extent, same reason the
    // "Show me the prompt now" test below already needs a scroll.
    await tester.scrollUntilVisible(find.text('My phone isn\'t listed'), 300);

    expect(find.textContaining('Xiaomi'), findsOneWidget);
    expect(find.textContaining('Oppo'), findsOneWidget);
    expect(find.textContaining('Vivo'), findsOneWidget);
    expect(find.textContaining('Samsung'), findsOneWidget);
    expect(find.text('My phone isn\'t listed'), findsOneWidget);
  });

  testWidgets('matched manufacturer is first, highlighted, and find-hint is shown', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StatusScreen(
        checkPermission: () async => false,
        requestPermission: () async => true,
        onShowPromptNow: ({required screenWidth, required screenHeight}) {},
        checkBatteryExemption: () async => true,
        requestBatteryExemption: () async {},
        readManufacturer: () async => 'vivo',
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining(overlayPermissionFindHint), findsOneWidget);
    expect(find.text('Looks like your phone'), findsOneWidget);
    expect(find.textContaining('Vivo'), findsOneWidget);
    // Matched tile is initially expanded — Vivo leave-smart-control step visible.
    expect(find.textContaining('Background power control'), findsOneWidget);
    expect(find.textContaining('Allow background power usage'), findsOneWidget);
    expect(find.textContaining('smart control'), findsOneWidget);
  });

  testWidgets('"Show me the prompt now" invokes the trigger with true device pixel dimensions', (tester) async {
    int? capturedWidth;
    int? capturedHeight;
    await tester.pumpWidget(MaterialApp(
      home: StatusScreen(
        checkPermission: () async => true,
        requestPermission: () async => true,
        onShowPromptNow: ({required screenWidth, required screenHeight}) {
          capturedWidth = screenWidth;
          capturedHeight = screenHeight;
        },
        checkBatteryExemption: () async => true,
        requestBatteryExemption: () async {},
      ),
    ));
    await tester.pump();

    // Capture what MediaQuery actually reports in this test surface, so the
    // assertion doesn't hardcode a device-pixel value that would be brittle
    // against test-framework default-size changes.
    final ctx = tester.element(find.byType(StatusScreen));
    final mq = MediaQuery.of(ctx);
    final mqSize = mq.size * mq.devicePixelRatio;

    // The button sits below the fold: this screen's ListView only builds
    // items within its viewport + cache extent, so the button doesn't exist
    // in the tree yet until scrolled into view.
    await tester.scrollUntilVisible(find.text('Show me the prompt now'), 200);
    await tester.tap(find.text('Show me the prompt now'));
    await tester.pump();

    expect(capturedWidth, mqSize.width.round());
    expect(capturedHeight, mqSize.height.round());
    expect(find.text('Requested — watch for the capture screen.'), findsOneWidget);
  });
}
