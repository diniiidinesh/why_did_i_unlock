import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'beacon_theme.dart';
import 'bubble_icons.dart';

/// @nodoc Kept for callers/tests that still import the old name.
const Color bubbleFillColor = BeaconColors.glassFill;

const double bubbleBlurSigma = 10;
const double bubbleCollapsedDp = 52;
const double bubbleExpandedHeightDp = 52;
const double bubbleExpandedMinWidthDp = 120;
const double bubbleExpandedMaxWidthDp = 240;
const double bubbleExpandedFontSize = 13;

/// Estimates expanded bubble width in dp for [text] (icon + label + two actions).
double expandedBubbleWidthDp(String text) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(
        fontSize: bubbleExpandedFontSize,
        fontWeight: FontWeight.w500,
      ),
    ),
    maxLines: 1,
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: bubbleExpandedMaxWidthDp);
  // icon 24 + gaps + snooze 32 + done 32 + horizontal padding
  const chrome = 24.0 + 8 + 8 + 32 + 8 + 32 + 16 + 12;
  final raw = chrome + painter.width;
  return raw.clamp(bubbleExpandedMinWidthDp, bubbleExpandedMaxWidthDp);
}

List<BoxShadow> get _beaconGlow => const [
      BoxShadow(
        color: BeaconColors.amberGlow,
        blurRadius: 12,
        spreadRadius: 0.5,
        offset: Offset(0, 0),
      ),
      BoxShadow(
        color: Color(0x33000000),
        blurRadius: 8,
        offset: Offset(0, 3),
      ),
    ];

/// Shared frosted shell: blur + black glass @ 60% + amber rim (1.5dp).
class _BeaconGlassShell extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;
  final Widget child;

  const _BeaconGlassShell({
    this.width,
    required this.height,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: _beaconGlow,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: bubbleBlurSigma,
            sigmaY: bubbleBlurSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              color: BeaconColors.glassFill,
              border: Border.all(
                color: BeaconColors.amber,
                width: 1.5,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Hybrid chat-head bubble: collapsed icon-only, or expanded with Done + Snooze.
class BubbleWidget extends StatelessWidget {
  final String intentText;
  final bool expanded;
  final VoidCallback onDone;
  final VoidCallback onSnooze;
  final VoidCallback onToggleExpand;

  const BubbleWidget({
    super.key,
    required this.intentText,
    required this.expanded,
    required this.onDone,
    required this.onSnooze,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final letter = letterAvatarForCustomIntent(intentText);
    final icon = iconForIntentLabel(intentText);

    return Semantics(
      label: intentText,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: expanded
            ? _ExpandedBubble(
                intentText: intentText,
                letter: letter,
                icon: icon,
                onDone: onDone,
                onSnooze: onSnooze,
                onToggleExpand: onToggleExpand,
              )
            : _CollapsedBubble(
                letter: letter,
                icon: icon,
                onTap: onToggleExpand,
              ),
      ),
    );
  }
}

class _CollapsedBubble extends StatelessWidget {
  final String? letter;
  final IconData icon;
  final VoidCallback onTap;

  const _CollapsedBubble({
    required this.letter,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(bubbleCollapsedDp / 2);
    return GestureDetector(
      onTap: onTap,
      child: _BeaconGlassShell(
        width: bubbleCollapsedDp,
        height: bubbleCollapsedDp,
        borderRadius: radius,
        child: Center(
          child: letter == null
              ? Icon(icon, color: BeaconColors.onGlass, size: 24)
              : Text(
                  letter!,
                  style: const TextStyle(
                    color: BeaconColors.onGlass,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }
}

class _ExpandedBubble extends StatelessWidget {
  final String intentText;
  final String? letter;
  final IconData icon;
  final VoidCallback onDone;
  final VoidCallback onSnooze;
  final VoidCallback onToggleExpand;

  const _ExpandedBubble({
    required this.intentText,
    required this.letter,
    required this.icon,
    required this.onDone,
    required this.onSnooze,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(bubbleExpandedHeightDp / 2);
    return _BeaconGlassShell(
      height: bubbleExpandedHeightDp,
      borderRadius: radius,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, right: 8),
        child: Row(
          children: [
            GestureDetector(
              onTap: onToggleExpand,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 28,
                height: bubbleExpandedHeightDp,
                child: Center(
                  child: letter == null
                      ? Icon(icon, color: BeaconColors.onGlass, size: 22)
                      : Text(
                          letter!,
                          style: const TextStyle(
                            color: BeaconColors.onGlass,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                intentText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: BeaconColors.onGlass,
                  fontSize: bubbleExpandedFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 4),
            _BubbleAction(
              background: BeaconColors.onGlass.withValues(alpha: 0.18),
              icon: Icons.notifications_paused,
              iconColor: BeaconColors.onGlass,
              semanticLabel: 'Snooze',
              onTap: onSnooze,
            ),
            const SizedBox(width: 6),
            _BubbleAction(
              background: BeaconColors.onGlass,
              icon: Icons.check,
              iconColor: BeaconColors.onAmber,
              semanticLabel: 'Done',
              onTap: onDone,
            ),
          ],
        ),
      ),
    );
  }
}

class _BubbleAction extends StatelessWidget {
  final Color background;
  final IconData icon;
  final Color iconColor;
  final String semanticLabel;
  final VoidCallback onTap;

  const _BubbleAction({
    required this.background,
    required this.icon,
    required this.iconColor,
    required this.semanticLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: background,
            shape: BoxShape.circle,
            border: Border.all(
              color: BeaconColors.amber.withValues(alpha: 0.5),
              width: 0.75,
            ),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }
}
