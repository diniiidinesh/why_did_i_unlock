import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/bubble_icons.dart';
import 'package:why_did_i_unlock/bubble_widget.dart';

void main() {
  group('iconForIntentLabel', () {
    test('maps current verb defaults', () {
      expect(iconForIntentLabel('Check mail'), Icons.mail_outline);
      expect(iconForIntentLabel('Message someone'), Icons.chat);
      expect(iconForIntentLabel('Book a cab'), Icons.local_taxi);
      expect(iconForIntentLabel('Order food'), Icons.restaurant);
      expect(iconForIntentLabel('Pay someone'), Icons.account_balance_wallet);
    });

    test('still maps prior verb and legacy defaults for history bubbles', () {
      expect(iconForIntentLabel('Watch reels'), Icons.play_circle_outline);
      expect(iconForIntentLabel('Payments'), Icons.account_balance_wallet);
      expect(iconForIntentLabel('Calls'), Icons.call);
      expect(iconForIntentLabel('Messages'), Icons.chat);
      expect(iconForIntentLabel('Food Order'), Icons.restaurant);
      expect(iconForIntentLabel('Commute'), Icons.directions_car);
    });

    test('unknown falls back to flag', () {
      expect(iconForIntentLabel('Buy groceries'), Icons.flag);
    });
  });

  group('letterAvatarForCustomIntent', () {
    test('null for seed presets (verb and legacy)', () {
      expect(letterAvatarForCustomIntent('Message someone'), isNull);
      expect(letterAvatarForCustomIntent('Messages'), isNull);
    });

    test('first letter for custom', () {
      expect(letterAvatarForCustomIntent('buy milk'), 'B');
    });
  });

  group('expandedBubbleWidthDp', () {
    test('clamps short and long text', () {
      final short = expandedBubbleWidthDp('Hi');
      expect(short, greaterThanOrEqualTo(bubbleExpandedMinWidthDp));
      expect(short, lessThanOrEqualTo(bubbleExpandedMaxWidthDp));
      expect(
        expandedBubbleWidthDp('x' * 100),
        bubbleExpandedMaxWidthDp,
      );
      final mid = expandedBubbleWidthDp('Messages');
      expect(mid, greaterThanOrEqualTo(bubbleExpandedMinWidthDp));
      expect(mid, lessThanOrEqualTo(bubbleExpandedMaxWidthDp));
    });
  });

  group('BubbleWidget', () {
    testWidgets('collapsed shows icon only, tap toggles', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BubbleWidget(
              intentText: 'Messages',
              expanded: false,
              onDone: () {},
              onSnooze: () {},
              onToggleExpand: () => toggled = true,
            ),
          ),
        ),
      );
      expect(find.text('Messages'), findsNothing);
      expect(find.byIcon(Icons.chat), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chat));
      expect(toggled, isTrue);
    });

    testWidgets('expanded shows text, Done and Snooze', (tester) async {
      var done = false;
      var snoozed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 240,
              height: 56,
              child: BubbleWidget(
                intentText: 'Messages',
                expanded: true,
                onDone: () => done = true,
                onSnooze: () => snoozed = true,
                onToggleExpand: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Messages'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.notifications_paused), findsOneWidget);
      await tester.tap(find.byIcon(Icons.check));
      expect(done, isTrue);
      await tester.tap(find.byIcon(Icons.notifications_paused));
      expect(snoozed, isTrue);
    });

    testWidgets('custom intent uses letter avatar when collapsed', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BubbleWidget(
              intentText: 'yoga class',
              expanded: false,
              onDone: () {},
              onSnooze: () {},
              onToggleExpand: () {},
            ),
          ),
        ),
      );
      expect(find.text('Y'), findsOneWidget);
    });
  });
}
