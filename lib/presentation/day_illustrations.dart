import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'itstheday_theme.dart';

enum ClockSparkState { ready, inProgress, complete, overdue }

/// A small original state illustration for moments and goals.
///
/// The mark uses a solid clock silhouette and two sparks instead of a stock
/// icon or borrowed character. It is deliberately static; state changes are
/// communicated by its palette and shape, not an idle animation.
class ClockSparkIllustration extends StatelessWidget {
  const ClockSparkIllustration({
    super.key,
    this.state = ClockSparkState.ready,
    this.size = 56,
    this.semanticLabel,
  });

  final ClockSparkState state;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: semanticLabel ?? _defaultLabel(state),
      child: FittedBox(
        fit: BoxFit.contain,
        child: SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _ClockSparkPainter(
              state: state,
              ink: Theme.of(context).colorScheme.onSurface,
              paper: Theme.of(context).colorScheme.surface,
            ),
          ),
        ),
      ),
    );
  }

  String _defaultLabel(ClockSparkState value) => switch (value) {
    ClockSparkState.ready => 'Ready clock and spark illustration',
    ClockSparkState.inProgress => 'Progress clock and spark illustration',
    ClockSparkState.complete => 'Complete clock and spark illustration',
    ClockSparkState.overdue => 'Overdue clock and spark illustration',
  };
}

class _ClockSparkPainter extends CustomPainter {
  _ClockSparkPainter({
    required this.state,
    required this.ink,
    required this.paper,
  });

  final ClockSparkState state;
  final Color ink;
  final Color paper;

  @override
  void paint(Canvas canvas, Size size) {
    final shortest = size.shortestSide;
    if (shortest <= 0) return;

    // Paint the illustration in a centered square so a tight rectangular
    // constraint cannot push either original spark outside the canvas.
    final artSide = shortest * .86;
    final art = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: artSide,
      height: artSide,
    );
    final origin = Offset(art.left + artSide * .5, art.top + artSide * .52);
    final accent = _accent;
    final secondary = _secondary;
    final stroke = artSide * .055;

    final halo = Paint()..color = accent.withValues(alpha: .18);
    canvas.drawCircle(
      origin.translate(artSide * -.08, artSide * .03),
      artSide * .38,
      halo,
    );

    final plate = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: origin.translate(artSide * .02, artSide * .04),
          width: artSide * .66,
          height: artSide * .66,
        ),
        Radius.circular(artSide * .18),
      ),
      plate,
    );

    final face = Paint()..color = paper;
    canvas.drawCircle(origin, artSide * .235, face);
    final ring = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(origin, artSide * .235, ring);

    final hand = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    final handAngle = switch (state) {
      ClockSparkState.ready => -.9,
      ClockSparkState.inProgress => .35,
      ClockSparkState.complete => .75,
      ClockSparkState.overdue => 2.45,
    };
    canvas.drawLine(
      origin,
      origin + Offset(math.cos(handAngle), math.sin(handAngle)) * artSide * .15,
      hand,
    );
    canvas.drawLine(origin, origin + Offset(0, -artSide * .14), hand);
    canvas.drawCircle(origin, artSide * .035, Paint()..color = secondary);

    _drawSpark(
      canvas,
      center: Offset(art.left + artSide * .77, art.top + artSide * .2),
      radius: artSide * .12,
      color: secondary,
    );
    _drawSpark(
      canvas,
      center: Offset(art.left + artSide * .2, art.top + artSide * .77),
      radius: artSide * .065,
      color: accent,
    );

    if (state == ClockSparkState.complete) {
      final check = Paint()
        ..color = paper
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()
        ..moveTo(art.left + artSide * .68, art.top + artSide * .72)
        ..lineTo(art.left + artSide * .75, art.top + artSide * .79)
        ..lineTo(art.left + artSide * .88, art.top + artSide * .63);
      canvas.drawPath(path, check);
    }
  }

  void _drawSpark(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
  }) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final angle = -math.pi / 2 + (i * math.pi / 4);
      final distance = i.isEven ? radius : radius * .36;
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  Color get _accent => switch (state) {
    ClockSparkState.ready => ItsTheDayPalette.mintStrong,
    ClockSparkState.inProgress => ItsTheDayPalette.skyStrong,
    ClockSparkState.complete => ItsTheDayPalette.amberStrong,
    ClockSparkState.overdue => ItsTheDayPalette.coralStrong,
  };

  Color get _secondary => switch (state) {
    ClockSparkState.ready => ItsTheDayPalette.amberStrong,
    ClockSparkState.inProgress => ItsTheDayPalette.mintStrong,
    ClockSparkState.complete => ItsTheDayPalette.mintStrong,
    ClockSparkState.overdue => ItsTheDayPalette.amberStrong,
  };

  @override
  bool shouldRepaint(covariant _ClockSparkPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.ink != ink ||
      oldDelegate.paper != paper;
}
