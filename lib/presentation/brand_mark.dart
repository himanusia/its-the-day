import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'itstheday_theme.dart';

/// The product mark: a clock-and-spark drawn in code so it stays original,
/// crisp at every size, and independent of borrowed mascot artwork.
class ItsTheDayMark extends StatelessWidget {
  const ItsTheDayMark({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: "It's the Day! mark",
      child: CustomPaint(
        size: Size.square(size),
        painter: const _ItsTheDayMarkPainter(
          background: ItsTheDayPalette.ink,
          ring: ItsTheDayPalette.mintStrong,
          hand: ItsTheDayPalette.mint,
          spark: ItsTheDayPalette.amber,
        ),
      ),
    );
  }
}

class _ItsTheDayMarkPainter extends CustomPainter {
  const _ItsTheDayMarkPainter({
    required this.background,
    required this.ring,
    required this.hand,
    required this.spark,
  });

  final Color background;
  final Color ring;
  final Color hand;
  final Color spark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shortest = size.shortestSide;
    final radius = shortest * .27;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()..color = background,
    );
    final center = size.center(Offset.zero);
    final outer = size.shortestSide * .324;
    final inner = size.shortestSide * .25;
    canvas.drawCircle(center, outer, Paint()..color = ring);
    canvas.drawCircle(center, inner, Paint()..color = background);

    final handPaint = Paint()
      ..color = hand
      ..strokeCap = StrokeCap.round
      ..strokeWidth = size.shortestSide * .075;
    canvas.drawLine(
      center,
      center + Offset(0, -size.shortestSide * .17),
      handPaint,
    );
    canvas.drawLine(
      center,
      center + Offset(size.shortestSide * .14, size.shortestSide * .08),
      handPaint,
    );
    canvas.drawCircle(center, size.shortestSide * .052, Paint()..color = spark);

    final sparkCenter = Offset(size.width * .76, size.height * .23);
    final sparkPaint = Paint()..color = spark;
    final path = Path()
      ..moveTo(sparkCenter.dx, sparkCenter.dy - shortest * .12)
      ..lineTo(
        sparkCenter.dx + shortest * .045,
        sparkCenter.dy - shortest * .045,
      )
      ..lineTo(sparkCenter.dx + shortest * .12, sparkCenter.dy)
      ..lineTo(
        sparkCenter.dx + shortest * .045,
        sparkCenter.dy + shortest * .045,
      )
      ..lineTo(sparkCenter.dx, sparkCenter.dy + shortest * .12)
      ..lineTo(
        sparkCenter.dx - shortest * .045,
        sparkCenter.dy + shortest * .045,
      )
      ..lineTo(sparkCenter.dx - shortest * .12, sparkCenter.dy)
      ..lineTo(
        sparkCenter.dx - shortest * .045,
        sparkCenter.dy - shortest * .045,
      )
      ..close();
    canvas.drawPath(path, sparkPaint);
  }

  @override
  bool shouldRepaint(covariant _ItsTheDayMarkPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.ring != ring ||
      oldDelegate.hand != hand ||
      oldDelegate.spark != spark;
}

/// A card-like interaction with a brief press depression and keyboard support.
/// Goal cards and other existing home surfaces can use it without adopting a
/// new dependency or an idle animation.
class TactileSurface extends StatefulWidget {
  const TactileSurface({
    super.key,
    required this.child,
    required this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final BorderRadius borderRadius;
  final String? semanticLabel;

  @override
  State<TactileSurface> createState() => _TactileSurfaceState();
}

class _TactileSurfaceState extends State<TactileSurface> {
  bool _pressed = false;
  bool _focused = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  void _activate() => widget.onTap();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 100);
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      onTap: _activate,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.enter): _activate,
          const SingleActivator(LogicalKeyboardKey.space): _activate,
        },
        child: Focus(
          onFocusChange: (value) {
            if (mounted) setState(() => _focused = value);
          },
          child: Material(
            color: Colors.transparent,
            borderRadius: widget.borderRadius,
            child: InkWell(
              onTap: _activate,
              onTapDown: (_) => _setPressed(true),
              onTapUp: (_) => _setPressed(false),
              onTapCancel: () => _setPressed(false),
              borderRadius: widget.borderRadius,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
                transformAlignment: Alignment.center,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                decoration: BoxDecoration(
                  borderRadius: widget.borderRadius,
                  border: _focused
                      ? Border.all(
                          color: Theme.of(context).colorScheme.primary,
                          width: 2,
                        )
                      : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
