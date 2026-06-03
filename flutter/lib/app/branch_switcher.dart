import 'package:flutter/material.dart';

/// Replaces go_router's default [IndexedStack] with a crossfade transition
/// between shell branches — new branch fades in while the old branch fades out.
///
/// All branches stay mounted (like [IndexedStack]) so their navigation state
/// is preserved across switches.
///
/// Used via [StatefulShellRoute.indexedStack]'s `navigatorContainerBuilder`.
class BranchSwitcher extends StatefulWidget {
  const BranchSwitcher({
    super.key,
    required this.currentIndex,
    required this.children,
  });

  final int currentIndex;
  final List<Widget> children;

  @override
  State<BranchSwitcher> createState() => _BranchSwitcherState();
}

class _BranchSwitcherState extends State<BranchSwitcher>
    with TickerProviderStateMixin {
  int _prevIndex = 0;
  late final AnimationController _ctrl;
  late final Animation<double> _oldFadeOut;
  late final Animation<double> _newFadeIn;

  @override
  void initState() {
    super.initState();
    _prevIndex = widget.currentIndex;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _oldFadeOut = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
    _newFadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.addListener(_onTick);
    _ctrl.addStatusListener(_onStatus);

    // Warm up opacity shaders after first frame to prevent jank on the
    // first real tab switch. Since currentIndex == _prevIndex, both
    // branches map to the same child (opacity 1.0), so this is invisible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ctrl.forward();
    });
  }

  void _onTick() => setState(() {});

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      setState(() {
        _prevIndex = widget.currentIndex;
        _ctrl.reset();
      });
    }
  }

  @override
  void didUpdateWidget(BranchSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentIndex != widget.currentIndex) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTick);
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final animating = _ctrl.isAnimating;

    return Stack(
      children: List.generate(widget.children.length, (i) {
        final isCurrent = i == widget.currentIndex;
        final isPrev = i == _prevIndex;

        bool visible;
        double opacity;

        if (!animating) {
          visible = isCurrent;
          opacity = 1.0;
        } else {
          visible = isCurrent || isPrev;
          if (isCurrent && !isPrev) {
            opacity = _newFadeIn.value;
          } else if (isPrev && !isCurrent) {
            opacity = _oldFadeOut.value;
          } else {
            opacity = 1.0; // same branch
          }
          if (opacity == 0.0) visible = false;
        }

        return Positioned.fill(
          child: Offstage(
            offstage: !visible,
            child: IgnorePointer(
              ignoring: !isCurrent,
              child: Opacity(
                opacity: opacity,
                child: widget.children[i],
              ),
            ),
          ),
        );
      }),
    );
  }
}
