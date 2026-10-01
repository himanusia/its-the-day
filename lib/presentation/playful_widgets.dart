import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Returns a motion duration that respects the platform accessibility setting.
Duration playfulMotionDuration(BuildContext context, Duration duration) {
  return MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}

/// A light surface with a crisp outline and a small tactile bottom edge.
///
/// Unlike an elevated Material card, this primitive keeps the canvas quiet and
/// gives important surfaces a deliberate, pressable silhouette.
class PlayfulPanel extends StatelessWidget {
  const PlayfulPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.bottomEdge = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final BorderRadius borderRadius;
  final bool bottomEdge;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final line = borderColor ?? colors.outlineVariant;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: borderRadius,
        border: Border.all(color: line, width: 1.2),
        boxShadow: bottomEdge
            ? [
                BoxShadow(
                  color: line.withValues(alpha: .48),
                  blurRadius: 0,
                  offset: const Offset(0, 3),
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: child,
    );
  }
}

enum PlayfulButtonTone { primary, secondary, quiet, danger }

/// A compact, rounded action with a tactile press depression.
///
/// It is intentionally built on Material primitives so it keeps ink feedback,
/// focus traversal, semantic button roles, and keyboard activation without a
/// dependency on a component package.
class PlayfulButton extends StatefulWidget {
  const PlayfulButton({
    super.key,
    required this.child,
    this.onPressed,
    this.semanticLabel,
    this.tone = PlayfulButtonTone.primary,
    this.expand = false,
  });

  PlayfulButton.icon({
    super.key,
    required IconData icon,
    required Widget label,
    this.onPressed,
    this.semanticLabel,
    this.tone = PlayfulButtonTone.primary,
    this.expand = false,
  }) : child = _PlayfulButtonContent(icon: icon, label: label);

  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final PlayfulButtonTone tone;
  final bool expand;

  @override
  State<PlayfulButton> createState() => _PlayfulButtonState();
}

class _PlayfulButtonContent extends StatelessWidget {
  const _PlayfulButtonContent({required this.icon, required this.label});

  final IconData icon;
  final Widget label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 9),
        Flexible(child: label),
      ],
    );
  }
}

class _PlayfulButtonState extends State<PlayfulButton> {
  bool _pressed = false;
  bool _focused = false;
  bool _hovered = false;

  bool get _enabled => widget.onPressed != null;

  void _activate() {
    if (_enabled) widget.onPressed!();
  }

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, border) = _colors(colors);
    final duration = playfulMotionDuration(
      context,
      const Duration(milliseconds: 110),
    );
    final radius = BorderRadius.circular(14);
    final shadow = _enabled && !_pressed
        ? [
            BoxShadow(
              color: colors.shadow.withValues(alpha: 0.18),
              blurRadius: 0,
              offset: const Offset(0, 3),
            ),
          ]
        : const <BoxShadow>[];

    final button = AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      transform: Matrix4.translationValues(0, _pressed ? 2 : 0, 0),
      transformAlignment: Alignment.center,
      constraints: const BoxConstraints(minHeight: 48),
      width: widget.expand ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _enabled ? background : colors.surfaceContainerHighest,
        borderRadius: radius,
        border: Border.all(
          color: _focused
              ? foreground
              : _enabled
              ? border
              : colors.onSurface.withValues(alpha: 0.12),
          width: _focused ? 2 : 1,
        ),
        boxShadow: shadow,
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: _enabled
              ? foreground
              : colors.onSurface.withValues(alpha: 0.42),
          fontWeight: FontWeight.w700,
        ),
        child: IconTheme.merge(
          data: IconThemeData(
            color: _enabled
                ? foreground
                : colors.onSurface.withValues(alpha: 0.42),
          ),
          child: Align(
            alignment: Alignment.center,
            widthFactor: widget.expand ? null : 1,
            child: widget.child,
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      button: true,
      enabled: _enabled,
      label: widget.semanticLabel,
      onTap: _enabled ? _activate : null,
      child: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.enter): _activate,
          const SingleActivator(LogicalKeyboardKey.space): _activate,
        },
        child: Focus(
          canRequestFocus: _enabled,
          onFocusChange: (value) {
            if (mounted) setState(() => _focused = value);
          },
          child: MouseRegion(
            cursor: _enabled
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            onEnter: (_) {
              if (mounted) setState(() => _hovered = true);
            },
            onExit: (_) {
              if (mounted) setState(() => _hovered = false);
            },
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: _enabled ? _activate : null,
                onTapDown: _enabled ? (_) => _setPressed(true) : null,
                onTapUp: _enabled ? (_) => _setPressed(false) : null,
                onTapCancel: _enabled ? () => _setPressed(false) : null,
                borderRadius: radius,
                splashColor: foreground.withValues(alpha: 0.12),
                highlightColor: foreground.withValues(alpha: 0.06),
                child: button,
              ),
            ),
          ),
        ),
      ),
    );
  }

  (Color, Color, Color) _colors(ColorScheme colors) {
    switch (widget.tone) {
      case PlayfulButtonTone.primary:
        return (
          colors.primary,
          colors.onPrimary,
          colors.primary.withValues(alpha: 0.7),
        );
      case PlayfulButtonTone.secondary:
        return (
          colors.surfaceContainerHighest,
          colors.onSurface,
          colors.primary.withValues(alpha: 0.38),
        );
      case PlayfulButtonTone.quiet:
        return (
          _hovered
              ? colors.surfaceContainerHighest
              : colors.surface.withValues(alpha: 0.01),
          colors.onSurface,
          colors.onSurface.withValues(alpha: 0.2),
        );
      case PlayfulButtonTone.danger:
        return (
          colors.errorContainer,
          colors.onErrorContainer,
          colors.error.withValues(alpha: 0.65),
        );
    }
  }
}

/// A wrap-safe goal kind choice with a clear selected state.
class PlayfulChoice extends StatelessWidget {
  const PlayfulChoice({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: '$label${selected ? ', selected' : ''}. $description',
      onTap: enabled ? onTap : null,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: AnimatedContainer(
            duration: playfulMotionDuration(
              context,
              const Duration(milliseconds: 160),
            ),
            constraints: const BoxConstraints(minHeight: 70),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected
                  ? colors.primary.withValues(alpha: 0.14)
                  : colors.surfaceContainerHighest.withValues(alpha: 0.68),
              borderRadius: radius,
              border: Border.all(
                color: selected
                    ? colors.primary
                    : colors.onSurface.withValues(alpha: 0.13),
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected
                      ? colors.primary
                      : colors.onSurface.withValues(alpha: 0.68),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: 0.66),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: selected
                      ? colors.primary
                      : colors.onSurface.withValues(alpha: 0.38),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A progress pill that animates only between real values and never exceeds
/// the track. The caller can show the uncapped total beside it.
class PlayfulProgressBar extends StatelessWidget {
  const PlayfulProgressBar({
    super.key,
    required this.value,
    required this.semanticLabel,
    this.height = 14,
  });

  final double value;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final clamped = value.clamp(0.0, 1.0).toDouble();
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: semanticLabel,
      value: '${(clamped * 100).round()} percent',
      child: SizedBox(
        height: height,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: clamped),
            duration: playfulMotionDuration(
              context,
              const Duration(milliseconds: 420),
            ),
            curve: Curves.easeOutCubic,
            builder: (context, animated, _) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(color: colors.surfaceContainerHighest),
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: animated.clamp(0.0, 1.0).toDouble(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.primary,
                        borderRadius: BorderRadius.circular(height),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A 48dp checklist target with a small completion transition.
class PlayfulCheck extends StatelessWidget {
  const PlayfulCheck({
    super.key,
    required this.value,
    required this.label,
    this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    return Semantics(
      button: true,
      toggled: value,
      enabled: enabled,
      label: label,
      onTap: enabled ? () => onChanged!(!value) : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: InkResponse(
          onTap: enabled ? () => onChanged!(!value) : null,
          containedInkWell: true,
          borderRadius: BorderRadius.circular(18),
          child: Center(
            child: AnimatedContainer(
              duration: playfulMotionDuration(
                context,
                const Duration(milliseconds: 180),
              ),
              curve: Curves.easeOutBack,
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: value ? colors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: value
                      ? colors.primary
                      : colors.onSurface.withValues(alpha: 0.42),
                  width: 2,
                ),
              ),
              child: AnimatedSwitcher(
                duration: playfulMotionDuration(
                  context,
                  const Duration(milliseconds: 180),
                ),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: value
                    ? ExcludeSemantics(
                        key: const ValueKey('checked'),
                        child: Icon(
                          Icons.check_rounded,
                          size: 21,
                          color: colors.onPrimary,
                        ),
                      )
                    : const SizedBox(key: ValueKey('unchecked')),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One-shot completion feedback. It never repeats or idles in the background.
class CelebrationBurst extends StatefulWidget {
  const CelebrationBurst({super.key, this.onFinished});

  final VoidCallback? onFinished;

  @override
  State<CelebrationBurst> createState() => _CelebrationBurstState();
}

class _CelebrationBurstState extends State<CelebrationBurst>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  bool _reducedHandled = false;
  bool _finished = false;

  void _finish() {
    if (_finished) return;
    _finished = true;
    widget.onFinished?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null || _reducedHandled) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reducedHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
      return;
    }
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 820),
          )
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _finish();
          })
          ..forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animation = _controller == null
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(parent: _controller!, curve: Curves.easeOutCubic);
    final colors = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: SizedBox.expand(
        child: Semantics(
          liveRegion: true,
          label: 'Goal complete',
          child: AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final progress = animation.value;
              return Stack(
                children: [
                  Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Transform.scale(
                        scale: 0.86 + (0.14 * progress),
                        child: Opacity(
                          opacity: (0.35 + (0.65 * progress))
                              .clamp(0.0, 1.0)
                              .toDouble(),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Material(
                              color: colors.primary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: colors.onPrimary.withValues(
                                    alpha: .35,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      color: colors.onPrimary,
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text(
                                        'Goal complete!',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(color: colors.onPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _CelebrationPainter(
                        progress: progress,
                        color: colors.secondary,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  const _CelebrationPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: (1 - progress) * .7);
    final origin = Offset(size.width / 2, 62);
    for (var i = 0; i < 10; i++) {
      final angle = (i * 0.63) - 1.4;
      final distance = 30 + (progress * 95);
      final point =
          origin +
          Offset(math.cos(angle) * distance, math.sin(angle) * distance);
      canvas.drawCircle(point, 3.5 * (1 - progress * .55), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CelebrationPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
