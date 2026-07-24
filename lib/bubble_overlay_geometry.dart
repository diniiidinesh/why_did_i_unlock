/// Pure geometry for bubble overlay placement under
/// [OverlayAlignment.centerRight] gravity (flutter_overlay_window).
///
/// With that gravity: `x == 0` is flush right; larger `x` shifts left.
/// `y` is an offset from vertical center. Kept free of Flutter plugins so
/// unit tests can lock the math that previously hid the bubble (`y=-376`)
/// or left-dock expand off-screen.
library;

/// Whether the bubble's horizontal center is on the left half of the screen.
bool bubbleDockedLeft({
  required double x,
  required double widthDp,
  required double screenWidthDp,
}) {
  if (screenWidthDp <= 0) return false;
  return (x + widthDp / 2) > screenWidthDp / 2;
}

/// Target `x` (dp) for left or right dock under centerRight gravity.
double bubbleSnapX({
  required bool dockLeft,
  required double widthDp,
  required double screenWidthDp,
}) {
  if (screenWidthDp <= 0 || widthDp <= 0) return 0;
  if (!dockLeft) return 0;
  return (screenWidthDp - widthDp).clamp(0.0, screenWidthDp);
}

/// Clamp vertical offset so the bubble stays on-screen after rotation.
/// When [resetY] is true, returns 0 (vertical center) — used after a fresh
/// show or orientation reopen.
double bubbleClampY({
  required double y,
  required double heightDp,
  required double screenHeightDp,
  bool resetY = false,
}) {
  if (resetY) return 0;
  if (screenHeightDp <= 0 || heightDp <= 0) return 0;
  final maxY = screenHeightDp > heightDp ? (screenHeightDp - heightDp) / 2 : 0.0;
  return y.clamp(-maxY, maxY);
}
