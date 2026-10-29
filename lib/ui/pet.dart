import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 宠物此刻在干什么。只有「在等」「在想」「在干」这三种，别的都不必演。
enum PetMood { idle, thinking, working }

/// 应用的拟人形象：一枚圆的头像，轻轻地呼吸。
///
/// 只在几个空着的地方出现，不挤正文：空对话、正在想、宽屏还没选对话、关于页。
/// 原图是方的一张，这里裁成圆的，所以不论图里主体在哪个位置都不会露边。
class PetAvatar extends StatefulWidget {
  const PetAvatar({
    super.key,
    this.size = 64,
    this.mood = PetMood.idle,
    this.ring = true,
  });

  final double size;
  final PetMood mood;

  /// 外面那一圈发丝线。贴在小字旁边时可以关掉。
  final bool ring;

  @override
  State<PetAvatar> createState() => _PetAvatarState();
}

class _PetAvatarState extends State<PetAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.mood == PetMood.idle ? 3200 : 1700),
  )..repeat();

  @override
  void didUpdateWidget(PetAvatar old) {
    super.didUpdateWidget(old);
    final int want = widget.mood == PetMood.idle ? 3200 : 1700;
    if (_ctrl.duration!.inMilliseconds != want) {
      _ctrl.duration = Duration(milliseconds: want);
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool quiet =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    final Widget face = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: C.paper2,
        border: widget.ring ? Border.all(color: C.rule) : null,
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/pet/pet.png',
          fit: BoxFit.cover,
          // 主体大致在画面中间偏上，往下压一点就不会切到脸。
          alignment: const Alignment(0, -0.06),
          filterQuality: FilterQuality.medium,
          errorBuilder: (BuildContext ctx, Object error, StackTrace? stack) => Center(
            child: Icon(Icons.hexagon, size: widget.size * 0.5, color: C.blue),
          ),
        ),
      ),
    );
    if (quiet) return face;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext ctx, Widget? child) {
        final double t = _ctrl.value * 2 * math.pi;
        final double lift = widget.mood == PetMood.idle
            ? math.sin(t) * 1.4
            : math.sin(t) * 0.9;
        final double scale = 1 + (widget.mood == PetMood.idle ? 0.008 : 0.014) * math.sin(t);
        return Transform.translate(
          offset: Offset(0, lift),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: face,
    );
  }
}
