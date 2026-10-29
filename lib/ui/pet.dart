import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 宠物此刻在干什么。待机是常态，另外两个只在跑的时候露一下。
enum PetMood { idle, thinking, working }

extension PetMoodInfo on PetMood {
  /// 宠物旁边那一行小字。
  String get label => switch (this) {
        PetMood.idle => '待机',
        PetMood.thinking => '在想',
        PetMood.working => '在干',
      };
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
  static const String _asset = 'assets/pet/pet.png';

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _span,
  )..repeat();

  Duration get _span => Duration(milliseconds: widget.mood == PetMood.idle ? 3600 : 2000);

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
              // 待机只是呼吸；在想的时候多抬一点，像在点头。
              final double lift = widget.mood == PetMood.idle
                  ? math.sin(t) * 1.2
                  : math.sin(t) * 2.2;
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
        _asset,
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
