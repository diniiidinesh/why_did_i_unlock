import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/about_screen.dart';

void main() {
  testWidgets('renders app name, version, and every action row', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutScreen(launch: (_) async => true),
    ));
    await tester.pump();

    expect(find.text(appDisplayName), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Version $appVersion'), findsOneWidget);
    expect(find.text('Send feedback'), findsOneWidget);
    expect(find.text('Report a problem'), findsOneWidget);
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Rate on Play'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Support'), findsOneWidget);
  });

  testWidgets('an injected version overrides the appVersion constant', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutScreen(launch: (_) async => true, version: '9.9.9+9'),
    ));
    await tester.pump();

    expect(find.text('Version 9.9.9+9'), findsOneWidget);
  });

  testWidgets('tapping "Send feedback" launches a mailto: URI to the support address', (tester) async {
    Uri? launched;
    await tester.pumpWidget(MaterialApp(
      home: AboutScreen(launch: (uri) async {
        launched = uri;
        return true;
      }),
    ));
    await tester.pump();

    await tester.tap(find.text('Send feedback'));
    await tester.pump();

    expect(launched, isNotNull);
    expect(launched!.scheme, 'mailto');
    expect(launched!.path, feedbackEmail);
    expect(launched!.queryParameters['subject'], contains(appVersion));
    // No SnackBar — the injected launcher reported success.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('tapping "Report a problem" launches a mailto with auto-filled log', (tester) async {
    Uri? launched;
    await tester.pumpWidget(MaterialApp(
      home: AboutScreen(
        launch: (uri) async {
          launched = uri;
          return true;
        },
        problemLogSnapshot: () async => 'FAKE_STACK_LINE',
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Report a problem'));
    await tester.pumpAndSettle();

    expect(launched, isNotNull);
    expect(launched!.scheme, 'mailto');
    expect(launched!.path, feedbackEmail);
    expect(launched!.queryParameters['subject'], contains('problem report'));
    expect(launched!.queryParameters['body'], contains('FAKE_STACK_LINE'));
    expect(launched!.queryParameters['body'], contains('What happened?'));
  });

  testWidgets('tapping "Privacy policy" launches the published policy URL', (tester) async {
    Uri? launched;
    await tester.pumpWidget(MaterialApp(
      home: AboutScreen(launch: (uri) async {
        launched = uri;
        return true;
      }),
    ));
    await tester.pump();

    await tester.tap(find.text('Privacy policy'));
    await tester.pump();

    expect(launched, Uri.parse(privacyPolicyUrl));
  });

  testWidgets('a launch failure shows a SnackBar instead of failing silently', (tester) async {
    // The realistic on-device case today: the placeholder URL/address can't
    // actually be opened. The button must surface that, not do nothing.
    await tester.pumpWidget(MaterialApp(
      home: AboutScreen(launch: (_) async => false),
    ));
    await tester.pump();

    await tester.tap(find.text('Rate on Play'));
    await tester.pump();

    expect(find.text('Not on Google Play yet.'), findsOneWidget);
  });

  testWidgets('a launcher that throws is treated as failure, not a crash', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutScreen(launch: (_) async => throw Exception('no handler')),
    ));
    await tester.pump();

    await tester.tap(find.text('Share'));
    await tester.pump();

    expect(find.text('Nothing to share yet — no Play listing.'), findsOneWidget);
  });

  testWidgets('Support section shows no payment link', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: AboutScreen(launch: (_) async => true),
    ));
    await tester.pump();

    await tester.scrollUntilVisible(find.text('Support'), 300);
    await tester.pump();

    expect(find.text('Support'), findsOneWidget);
    expect(find.textContaining('support development'), findsOneWidget);
    expect(find.byType(TextButton), findsNothing);
    expect(find.byIcon(Icons.attach_money), findsNothing);
  });
}
