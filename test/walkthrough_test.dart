import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/brand.dart';
import 'package:why_did_i_unlock/walkthrough.dart';

void main() {
  Future<void> pumpWalkthrough(
    WidgetTester tester, {
    bool disableAnimations = false,
    bool standalone = false,
    VoidCallback? onStandaloneFinished,
  }) {
    return tester.pumpWidget(MaterialApp(
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(disableAnimations: disableAnimations),
          child: child!,
        );
      },
      home: Scaffold(
        backgroundColor: Colors.black,
        body: WalkthroughView(
          standalone: standalone,
          onStandaloneFinished: onStandaloneFinished,
        ),
      ),
    ));
  }

  testWidgets('advances through all 7 beats', (tester) async {
    await pumpWalkthrough(tester);
    await tester.pump();

    for (final beat in WalkthroughBeat.values) {
      expect(find.text(beat.caption), findsOneWidget, reason: beat.name);
      if (beat == WalkthroughBeat.values.last) break;
      await tester.pump(walkthroughBeatDuration);
      await tester.pump();
    }
  });

  testWidgets('Skip jumps to the last beat', (tester) async {
    await pumpWalkthrough(tester);
    await tester.pump();

    expect(find.text('You unlock.'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await tester.pump();

    expect(find.text(WalkthroughBeat.values.last.caption), findsOneWidget);
    expect(find.text('You unlock.'), findsNothing);
  });

  testWidgets('tap pauses auto-advance', (tester) async {
    await pumpWalkthrough(tester);
    await tester.pump();
    expect(find.text('You unlock.'), findsOneWidget);

    await tester.tap(find.byType(PageView));
    await tester.pump();

    await tester.pump(walkthroughBeatDuration);
    await tester.pump();
    expect(find.text('You unlock.'), findsOneWidget);
    expect(find.text('$appDisplayName asks why.'), findsNothing);
  });

  testWidgets('reduced motion renders the static caption list', (tester) async {
    await pumpWalkthrough(tester, disableAnimations: true);
    await tester.pump();

    expect(find.byType(PageView), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
    for (final beat in WalkthroughBeat.values) {
      expect(find.text(beat.caption), findsOneWidget, reason: beat.name);
    }
  });

  testWidgets('standalone Skip closes the walkthrough', (tester) async {
    var finished = false;
    await pumpWalkthrough(
      tester,
      standalone: true,
      onStandaloneFinished: () => finished = true,
    );
    await tester.pump();

    await tester.tap(find.text('Skip'));
    await tester.pump();
    expect(finished, isTrue);
  });
}
