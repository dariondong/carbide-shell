import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 宠物此刻在干什么。待机是常态，另外几个只在对应的时候露一下。
enum PetMood { idle, thinking, working, sleeping }

extension PetMoodInfo on PetMood {
  /// 宠物旁边那一行小字。
  String get label => switch (this) {
        PetMood.idle => '待机',
        PetMood.thinking => '在想',
        PetMood.working => '工作中',
        PetMood.sleeping => '睡觉',
      };

  /// 这一态用哪张立绘。
  String get asset => switch (this) {
        PetMood.idle => 'assets/pet/idle.png',
        PetMood.thinking || PetMood.working => 'assets/pet/work.png',
        PetMood.sleeping => 'assets/pet/sleep.png',
      };
}

/// 现在该画哪一态：有活在跑就是工作中，在等人答就是想，其余时候都在睡觉。
PetMood petMoodNow({required bool running, required bool waiting}) {
  if (running) return PetMood.working;
  if (waiting) return PetMood.thinking;
  return PetMood.sleeping;
}

/// 应用的拟人形象。是一张带透明底的立绘，不是头像框，所以贴在哪里都干净。
///
/// 只在几个空着的地方出现，不挤正文：空对话、正在想的那一行、宽屏还没选对话的右边、
/// 关于页。默认的待机动作只是很轻地呼吸；在跑的时候换快一点的节奏。
class PetAvatar extends StatefulWidget {
  const PetAvatar({
    super.key,
    this.size = 96,
    this.mood = PetMood.idle,
    this.showState = false,
  });

  /// 画多高。宽度按原图比例算。
  final double size;
  final PetMood mood;

  /// 底下要不要写一行「待机 / 在想 / 在干」。
  final bool showState;

  @override
  State<PetAvatar> createState() => _PetAvatarState();
}

class _PetAvatarState extends State<PetAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _span,
  )..repeat();

  Duration get _span => Duration(
      milliseconds: widget.mood == PetMood.sleeping
          ? 5200
          : (widget.mood == PetMood.idle ? 3600 : 2000));

  @override
  void didUpdateWidget(PetAvatar old) {
    super.didUpdateWidget(old);
    if (_ctrl.duration != _span) {
      _ctrl.duration = _span;
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
    final Widget figure = _figure();
    final Widget body = quiet
        ? figure
        : AnimatedBuilder(
            animation: _ctrl,
            builder: (BuildContext ctx, Widget? child) {
              final double t = _ctrl.value * 2 * math.pi;
              // 待机和睡觉只是呼吸；在想、在干的时候多抬一点。
              final double lift = switch (widget.mood) {
                PetMood.idle || PetMood.sleeping => math.sin(t) * 1.2,
                _ => math.sin(t) * 2.2,
              };
              final double scale =
                  1 + (widget.mood == PetMood.idle ? 0.006 : 0.012) * math.sin(t);
              return Transform.translate(
                offset: Offset(0, lift),
                child: Transform.scale(scale: scale, child: child),
              );
            },
            child: figure,
          );
    if (!widget.showState) return body;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        body,
        const SizedBox(height: 6),
        Text(widget.mood.label, style: C.monoSmall.copyWith(fontSize: 10)),
      ],
    );
  }

  Widget _figure() {
    return SizedBox(
      height: widget.size,
      child: Image.asset(
        widget.mood.asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // 小的那几处按目标尺寸解码，省下来的内存比清晰度值。
        cacheWidth: widget.size < 200 ? (widget.size * 2).round() : null,
        errorBuilder: (BuildContext ctx, Object error, StackTrace? stack) => SizedBox(
          height: widget.size,
          width: widget.size,
          child: Center(
            child: Icon(Icons.hexagon, size: widget.size * 0.5, color: C.blue),
          ),
        ),
      ),
    );
  }
}
