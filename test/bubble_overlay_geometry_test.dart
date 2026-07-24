import 'package:flutter_test/flutter_test.dart';
import 'package:why_did_i_unlock/bubble_overlay_geometry.dart';
import 'package:why_did_i_unlock/bubble_widget.dart';

void main() {
  // Portrait-ish logical size (~411×914 at 2.625 dpr on 1080×2400).
  const portraitW = 411.0;
  const portraitH = 914.0;
  // Landscape swap.
  const landscapeW = 914.0;
  const landscapeH = 411.0;
  const collapsed = bubbleCollapsedDp; // 52

  group('bubbleDockedLeft (centerRight gravity)', () {
    test('x=0 (right edge) is not left', () {
      expect(
        bubbleDockedLeft(x: 0, widthDp: collapsed, screenWidthDp: portraitW),
        isFalse,
      );
    });

    test('left dock x ≈ screenW - width is left', () {
      final x = bubbleSnapX(
        dockLeft: true,
        widthDp: collapsed,
        screenWidthDp: portraitW,
      );
      expect(
        bubbleDockedLeft(x: x, widthDp: collapsed, screenWidthDp: portraitW),
        isTrue,
      );
      // Matches on-device left snaps (~359 on ~411dp width).
      expect(x, closeTo(portraitW - collapsed, 0.01));
    });

    test('mid-screen after rotate uses landscape width for side', () {
      // Stale portrait left-x on a wider landscape screen → still left half.
      const staleLeftX = 359.0;
      expect(
        bubbleDockedLeft(
          x: staleLeftX,
          widthDp: collapsed,
          screenWidthDp: landscapeW,
        ),
        isFalse, // center is at ~385, landscape mid is 457 → right half
      );
    });
  });

  group('bubbleSnapX', () {
    test('right dock is always 0', () {
      expect(
        bubbleSnapX(dockLeft: false, widthDp: collapsed, screenWidthDp: landscapeW),
        0,
      );
    });

    test('left dock uses current screen width (not stale portrait)', () {
      final x = bubbleSnapX(
        dockLeft: true,
        widthDp: collapsed,
        screenWidthDp: landscapeW,
      );
      expect(x, closeTo(landscapeW - collapsed, 0.01));
      // Must not reuse portrait left x (~359) on landscape — that parks mid-screen.
      expect(x, isNot(closeTo(359, 1)));
    });

    test('stale portrait left-x on landscape is NOT a true left edge', () {
      // On-device TEST_PLAN 60: snaps logged x=359 after 2400x1080 rotate.
      const stalePortraitLeftX = 359.42857142857144;
      final trueLeft = bubbleSnapX(
        dockLeft: true,
        widthDp: collapsed,
        screenWidthDp: landscapeW,
      );
      expect(stalePortraitLeftX, lessThan(trueLeft - 100));
    });

    test('expanded width on left stays fully in bounds', () {
      final expanded = expandedBubbleWidthDp('Messages');
      final x = bubbleSnapX(
        dockLeft: true,
        widthDp: expanded,
        screenWidthDp: portraitW,
      );
      expect(x + expanded, lessThanOrEqualTo(portraitW + 0.01));
      expect(x, greaterThanOrEqualTo(0));
    });
  });

  group('bubbleClampY', () {
    test('resetY forces vertical center', () {
      expect(
        bubbleClampY(
          y: -376,
          heightDp: collapsed,
          screenHeightDp: landscapeH,
          resetY: true,
        ),
        0,
      );
    });

    test('clamps off-screen portrait y into landscape height', () {
      // On-device vanish: y=-376 with landscape height ~411.
      final clamped = bubbleClampY(
        y: -376,
        heightDp: collapsed,
        screenHeightDp: landscapeH,
      );
      final maxY = (landscapeH - collapsed) / 2;
      expect(clamped, greaterThanOrEqualTo(-maxY));
      expect(clamped, lessThanOrEqualTo(maxY));
      expect(clamped, isNot(-376));
    });

    test('in-range y unchanged', () {
      expect(
        bubbleClampY(y: 10, heightDp: collapsed, screenHeightDp: portraitH),
        10,
      );
    });
  });
}
