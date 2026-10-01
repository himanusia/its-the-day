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
      child: CustomPaint(
        size: Size.square(size),
        painter: _ClockSparkPainter(
          state: state,
          ink: Theme.of(context).colorScheme.onSurface,
          paper: Theme.of(context).colorScheme.surface,
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
    final origin = Offset(size.width * .5, size.height * .52);
    final accent = _accent;
    final secondary = _secondary;
    final stroke = shortest * .055;

    final halo = Paint()..color = accent.withValues(alpha: .18);
    canvas.drawCircle(
      origin.translate(shortest * -.08, shortest * .03),
      shortest * .38,
      halo,
    );

    final plate = Paint()..color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: origin.translate(shortest * .02, shortest * .04),
          width: shortest * .66,
          height: shortest * .66,
        ),
        Radius.circular(shortest * .18),
      ),
      plate,
    );

    final face = Paint()..color = paper;
    canvas.drawCircle(origin, shortest * .235, face);
    final ring = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(origin, shortest * .235, ring);

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
      origin +
          Offset(math.cos(handAngle), math.sin(handAngle)) * shortest * .15,
      hand,
    );
    canvas.drawLine(origin, origin + Offset(0, -shortest * .14), hand);
    canvas.drawCircle(origin, shortest * .035, Paint()..color = secondary);

    _drawSpark(
      canvas,
      center: Offset(size.width * .77, size.height * .2),
      radius: shortest * .12,
      color: secondary,
    );
    _drawSpark(
      canvas,
      center: Offset(size.width * .2, size.height * .77),
      radius: shortest * .065,
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
        ..moveTo(size.width * .68, size.height * .72)
        ..lineTo(size.width * .75, size.height * .79)
        ..lineTo(size.width * .88, size.height * .63);
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
