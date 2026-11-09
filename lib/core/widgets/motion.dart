import 'package:flutter/material.dart';

/// A tactile press response that leaves the Material button's semantics intact.
class PressMotion extends StatefulWidget {
  const PressMotion({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;
  @override
  State<PressMotion> createState() => _PressMotionState();
}

class _PressMotionState extends State<PressMotion> {
  bool _pressed = false;
  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
    onPointerUp: (_) => _setPressed(false),
    onPointerCancel: (_) => _setPressed(false),
    child: AnimatedScale(
      scale: _pressed && widget.enabled ? 0.98 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 120),
      curve: Curves.easeOutCubic,
      child: widget.child,
    ),
  );
}

Widget pageMotion(
  BuildContext context,
  Animation<double> animation,
  Widget child,
) {
  if (MediaQuery.disableAnimationsOf(context)) return child;
  final eased = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return FadeTransition(
    opacity: eased,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.025),
        end: Offset.zero,
      ).animate(eased),
      child: child,
    ),
  );
}
