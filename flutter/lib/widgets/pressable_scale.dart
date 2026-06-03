import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps a child widget (typically an ElevatedButton) with a scale + haptic
/// press animation. On tap-down: fires a light haptic tick and scales to 95%.
/// On tap-up or cancel: springs back to 100% with an elastic curve.
///
/// The GestureDetector uses HitTestBehavior.translucent so the inner button
/// still receives its own tap events and fires onPressed normally.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child});
  final Widget child;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _pressed = true);
      },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: _pressed
            ? const Duration(milliseconds: 80)
            : const Duration(milliseconds: 180),
        curve: _pressed ? Curves.easeIn : Curves.elasticOut,
        child: widget.child,
      ),
    );
  }
}
