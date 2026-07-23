import 'dart:math';

import 'package:flutter/material.dart';

/// One wedge of an [OutcomeDonut] — a labelled, coloured count. Deliberately
/// just data (no `IntentStore`/aggregation-query dependency here — see the
/// class doc on [OutcomeDonut]): T14 (insight queries) and T18 (Home cards)
/// own turning real `intent_log`/`unlock_log` rows into a `List<DonutSlice>`,
/// this widget only knows how to draw whatever list it's handed.
class DonutSlice {
  final String label;
  final double value;
  final Color color;

  const DonutSlice({required this.label, required this.value, required this.color});
}

/// A ring-style ("donut") breakdown chart with a legend, built as a bare
/// `CustomPainter` rather than a charting package — see `CLAUDE.md` §7/§9
/// (this repo's plan explicitly rejected `fl_chart`: a 3-5 slice donut is a
/// small, fixed amount of arc math, and every extra dependency is extra
/// weight on a background-service-carrying app that has to run well on
/// low-end devices).
///
/// Pure presentation: takes [slices] and draws them. It does not query
/// [IntentStore] itself and has no opinion on what the slices represent
/// (outcome kind, skip reason, anything else) — that separation is what lets
/// T14/T18 wire it up later without this file changing.
class OutcomeDonut extends StatelessWidget {
  /// The wedges to draw. An empty list, or a list whose values all sum to
  /// zero, renders the dedicated empty state below rather than dividing by
  /// zero — this is a real, expected state (a brand-new install has no
  /// events yet), not an error.
  final List<DonutSlice> slices;

  /// Outer diameter of the ring, logical pixels. Not hardcoded to a single
  /// call site's needs (`CLAUDE.md` §8 — never hardcode pixel sizes for a
  /// specific screen) so this widget can be reused at different sizes.
  final double size;

  /// Ring thickness. Kept as a fraction of [size] by default (see
  /// [_defaultStrokeWidth]) so the donut's proportions stay stable if a
  /// caller changes [size], rather than a fixed stroke looking too thin on
  /// a large ring or too thick on a small one.
  final double? strokeWidth;

  /// Short text drawn in the centre of the ring (e.g. a total count). Null
  /// renders no centre text at all, not an empty string measured for
  /// layout — avoids reserving space nobody asked for.
  final String? centerLabel;

  const OutcomeDonut({
    super.key,
    required this.slices,
    this.size = 160,
    this.strokeWidth,
    this.centerLabel,
  });

  double get _resolvedStrokeWidth => strokeWidth ?? size * 0.18;

  double get _total => slices.fold(0.0, (sum, s) => sum + s.value);

  @override
  Widget build(BuildContext context) {
    final total = _total;
    if (total <= 0) {
      return _EmptyDonut(size: size, strokeWidth: _resolvedStrokeWidth);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(size, size),
                painter: _DonutPainter(slices: slices, strokeWidth: _resolvedStrokeWidth),
              ),
              if (centerLabel != null)
                Text(
                  centerLabel!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _DonutLegend(slices: slices, total: total),
      ],
    );
  }
}

/// Neutral placeholder ring shown when there is nothing to chart yet (an
/// empty [OutcomeDonut.slices] list, or one that sums to zero — e.g. a fresh
/// install before any unlock has been logged). A dim full ring plus "No data
/// yet" reads as "this feature works, there's just nothing here" rather than
/// a blank space that looks broken.
class _EmptyDonut extends StatelessWidget {
  final double size;
  final double strokeWidth;

  const _EmptyDonut({required this.size, required this.strokeWidth});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            size: Size(size, size),
            painter: _EmptyRingPainter(strokeWidth: strokeWidth),
          ),
        ),
        const SizedBox(height: 12),
        const Text('No data yet', style: TextStyle(color: Colors.white54, fontSize: 13)),
      ],
    );
  }
}

class _EmptyRingPainter extends CustomPainter {
  final double strokeWidth;

  const _EmptyRingPainter({required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (min(size.width, size.height) - strokeWidth) / 2;
    final paint = Paint()
      ..color = Colors.white12
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _EmptyRingPainter oldDelegate) => oldDelegate.strokeWidth != strokeWidth;
}

/// Draws each [DonutSlice] as a stroked arc (a ring), not a filled pie
/// wedge. A stroke-based ring is simpler to get right than a multi-path pie
/// — no seams to render at the centre, and a zero-value slice just draws a
/// zero-length arc instead of needing special-cased path skipping.
///
/// Wedges start at 12 o'clock (`-pi/2`) and proceed clockwise in [slices]
/// order — a fixed, predictable convention so the same data always draws
/// the same picture and the legend order below matches the visual order.
class _DonutPainter extends CustomPainter {
  final List<DonutSlice> slices;
  final double strokeWidth;

  const _DonutPainter({required this.slices, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final total = slices.fold(0.0, (sum, s) => sum + s.value);
    if (total <= 0) return; // Guarded by the caller too; defensive against direct reuse.

    final center = size.center(Offset.zero);
    final radius = (min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    var startAngle = -pi / 2;
    for (final slice in slices) {
      if (slice.value <= 0) continue; // Zero-value slices contribute no arc and no gap artifact.
      final sweep = (slice.value / total) * 2 * pi;
      final paint = Paint()
        ..color = slice.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt; // Butt, not round — round caps overlap at slice boundaries.
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.strokeWidth != strokeWidth;
}

/// Colour-dot + label + value/percentage row per slice, below the ring.
/// Percentages are computed from the same [total] the ring uses so the two
/// never disagree even if a caller passes slices that don't sum to a round
/// number.
class _DonutLegend extends StatelessWidget {
  final List<DonutSlice> slices;
  final double total;

  const _DonutLegend({required this.slices, required this.total});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: slices.map((slice) {
        final pct = total > 0 ? (slice.value / total * 100).round() : 0;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: slice.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              '${slice.label} · $pct%',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        );
      }).toList(),
    );
  }
}
