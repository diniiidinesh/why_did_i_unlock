import 'package:flutter/material.dart';

import 'beacon_theme.dart';
import 'nudge_tuning.dart';

/// Copy for Home tooltips + first-visit banners (`§4C` / `§10` day-1 cards).
class DiscoveryCopy {
  static const settingsTitle = 'How often Beacon asks';
  static const settingsBody = 'Change the gap, quiet hours, and more.';
  static const manageTitle = 'Your reasons';
  static const manageBody = 'Add, reorder, or remove them.';
  static const gotIt = 'Got it';
}

enum DiscoveryTarget { settings, manage }

/// Pure queue / gate so tooltip tests don't need a full [HomeScreen].
class DiscoveryPolicy {
  const DiscoveryPolicy();

  /// Fallback Home banner once launches hit the threshold and a screen is
  /// still unopened. Prefer this over a tooltip so both don't nag at once.
  bool showFallbackBanner({
    required int launchCount,
    required bool settingsOpened,
    required bool manageOpened,
  }) {
    if (!NudgeTuning.fallbackBannerEnabled) return false;
    if (DiscoverySession.skipThisLaunch) return false;
    if (launchCount < NudgeTuning.nudgeBannerLaunchThreshold) return false;
    return !settingsOpened || !manageOpened;
  }

  DiscoveryTarget? nextTooltip({
    required bool hasUnlocks,
    required bool settingsOpened,
    required bool manageOpened,
    required int settingsShows,
    required int manageShows,
    Set<DiscoveryTarget> dismissedThisSession = const <DiscoveryTarget>{},
  }) {
    if (DiscoverySession.skipThisLaunch) return null;
    if (!hasUnlocks) return null;
    if (!dismissedThisSession.contains(DiscoveryTarget.settings) &&
        _eligible(opened: settingsOpened, shows: settingsShows)) {
      return DiscoveryTarget.settings;
    }
    if (!dismissedThisSession.contains(DiscoveryTarget.manage) &&
        _eligible(opened: manageOpened, shows: manageShows)) {
      return DiscoveryTarget.manage;
    }
    return null;
  }

  bool _eligible({required bool opened, required int shows}) {
    if (opened) return false;
    return shows < NudgeTuning.maxTooltipShows;
  }
}

bool discoveryTargetIsVisible(GlobalKey key) {
  final ctx = key.currentContext;
  if (ctx == null) return false;
  final box = ctx.findRenderObject();
  if (box is! RenderBox || !box.hasSize || box.size.isEmpty) return false;
  final topLeft = box.localToGlobal(Offset.zero);
  final bottomRight = topLeft + Offset(box.size.width, box.size.height);
  final size = MediaQuery.sizeOf(ctx);
  return bottomRight.dx > 0 &&
      bottomRight.dy > 0 &&
      topLeft.dx < size.width &&
      topLeft.dy < size.height;
}

/// Anchored overlay for Home feature discovery (`§4C.3`).
///
/// Position is computed from the target's [RenderBox] rather than
/// [CompositedTransformFollower]: a scrolling [ListView] plus a root
/// [Overlay] left the follower hundreds of pixels above the visible
/// button. The same [GlobalKey] already gates "don't show if not laid
/// out"; rebuilding this entry on scroll (`markNeedsBuild`) keeps it
/// stuck to the control.
OverlayEntry buildDiscoveryTooltipEntry({
  required GlobalKey targetKey,
  required DiscoveryTarget target,
  required VoidCallback onGotIt,
}) {
  final title = target == DiscoveryTarget.settings
      ? DiscoveryCopy.settingsTitle
      : DiscoveryCopy.manageTitle;
  final body = target == DiscoveryTarget.settings
      ? DiscoveryCopy.settingsBody
      : DiscoveryCopy.manageBody;
  final tooltipKey = target == DiscoveryTarget.settings
      ? const ValueKey('discovery-tooltip-settings')
      : const ValueKey('discovery-tooltip-manage');

  return OverlayEntry(
    opaque: false,
    builder: (context) {
      final box = targetKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return const SizedBox.shrink();
      final origin = box.localToGlobal(Offset.zero);
      final view = MediaQuery.sizeOf(context);
      // Sit just above the control so the tap target itself stays free
      // (`§4C.3`). Flip below if that would paint off the top of the screen.
      const tooltipWidth = 260.0;
      const estimatedHeight = 132.0;
      var top = origin.dy - estimatedHeight - 8;
      if (top < 8) top = origin.dy + box.size.height + 8;
      var left = origin.dx;
      if (left + tooltipWidth > view.width - 8) {
        left = view.width - tooltipWidth - 8;
      }
      if (left < 8) left = 8;
      return Positioned(
        left: left,
        top: top.clamp(8.0, view.height - estimatedHeight),
        child: Material(
          key: tooltipKey,
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: tooltipWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xF21A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: BeaconColors.amber.withValues(alpha: 0.7)),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: onGotIt,
                        child: const Text(DiscoveryCopy.gotIt),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// One-time "what this screen controls" banner. Tooltip says where; this
/// says what. Dismissible, never blocks the rest of the screen.
class FirstVisitBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;

  const FirstVisitBanner({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BeaconColors.amber.withValues(alpha: 0.16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
              tooltip: 'Dismiss',
            ),
          ],
        ),
      ),
    );
  }
}
