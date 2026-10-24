import 'dart:async';

import 'package:flutter/material.dart';

/// 进场：淡入 + 往上抬一小段。可以按次序错开，一页里的几块就不会一起蹦出来。
///
/// 系统开了「减少动态效果」时直接显示，不做动画。
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.lift = 10,
    this.duration = const Duration(milliseconds: 320),
  });

  final Widget child;
  final Duration delay;

  /// 起来多少个像素。
  final double lift;
  final Duration duration;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _curved =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  Timer? _timer;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final bool quiet =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (quiet) {
      _done = true;
      return;
    }
    if (widget.delay == Duration.zero) {
      _ctrl.forward();
      return;
    }
    _timer = Timer(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return AnimatedBuilder(
      animation: _curved,
      builder: (BuildContext ctx, Widget? child) => Opacity(
        opacity: _curved.value,
        child: Transform.translate(
          offset: Offset(0, widget.lift * (1 - _curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// 按下去缩一点。给人「这一下确实按到了」的手感，不改布局。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final HitTestBehavior behavior;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// 数字变了就滚一下：旧数字淡出、新数字淡入并稍稍上抬。
class RollingNumber extends StatelessWidget {
  const RollingNumber({
    super.key,
    required this.text,
    required this.style,
    this.alignment = Alignment.centerLeft,
  });

  final String text;
  final TextStyle style;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      layoutBuilder: (Widget? current, List<Widget> previous) => Stack(
        alignment: alignment,
        children: <Widget>[
          ...previous,
          if (current != null) current,
        ],
      ),
      transitionBuilder: (Widget child, Animation<double> anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.18),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: Text(text, key: ValueKey<String>(text), style: style),
    );
  }
}
