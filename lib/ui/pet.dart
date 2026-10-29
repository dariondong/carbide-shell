import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// 小猫此刻在干什么。每一态都有一张立绘，空着的地方按当时真发生的事挑一张，
/// 不为了好看随便换。
enum PetMood {
  idle,
  thinking,
  working,
  sleeping,
  happy,
  celebrating,
  waving,
  curious,
  loading,
  error,
}

extension PetMoodInfo on PetMood {
  /// 宠物旁边那一行小字。
  String get label => switch (this) {
        PetMood.idle => '待机',
        PetMood.thinking => '在想',
        PetMood.working => '工作中',
        PetMood.sleeping => '睡觉',
        PetMood.happy => '挺高兴',
        PetMood.celebrating => '办成了',
        PetMood.waving => '打招呼',
        PetMood.curious => '好奇',
        PetMood.loading => '在准备',
        PetMood.error => '出了点岔子',
      };

  /// 这一态用哪张立绘。文件名就是这一态的名字。
  String get asset => 'assets/pet/$name.png';

  /// 闲着的那几态。大一点的立绘会在这几张之间轮着换，一直在动才像活的。
  bool get rests => kPetResting.contains(this);
}

/// 轮着用的几张闲姿态：待机、好奇、招手、高兴。
const List<PetMood> kPetResting = <PetMood>[
  PetMood.idle,
  PetMood.curious,
  PetMood.waving,
  PetMood.happy,
];

/// 现在该画哪一态：有活在跑就是工作中，在等人答就是想，其余时候都在睡觉。
/// [greeting] 打开时，空对话里那只改成招手：它在等你开口，不是在睡。
PetMood petMoodNow({
  required bool running,
  required bool waiting,
  bool greeting = false,
}) {
  if (running) return PetMood.working;
  if (waiting) return PetMood.thinking;
  return greeting ? PetMood.waving : PetMood.sleeping;
}

/// 应用的拟人形象。是一张带透明底的立绘，不是头像框，所以贴在哪里都干净。
///
/// 只在几个空着的地方出现，不挤正文：空对话、正在想的那一行、宽屏还没选对话的右边、
/// 关于页、各页的空清单。默认的待机动作只是很轻地呼吸；闲在空地方的时候每六秒换一张
/// 姿势（待机/好奇/招手/高兴），在干活、等批准的时候换成对应的那几张。
class PetAvatar extends StatefulWidget {
  const PetAvatar({
    super.key,
    this.size = 96,
    this.mood = PetMood.idle,
    this.showState = false,
    this.cycle,
  });

  /// 画多高。宽度按原图比例算。
  final double size;
  final PetMood mood;

  /// 底下要不要写一行「待机 / 在想 / 在干」。
  final bool showState;

  /// 轮着换的姿势，第一张是 [mood] 自己。留空按尺寸定：大一点又是闲着的姿态，
  /// 就在 [kPetResting] 里轮；小的那一圈和干活、出错这些姿态只画一张。给一个空列表
  /// 就是不要它动。
  final List<PetMood>? cycle;

  @override
  State<PetAvatar> createState() => _PetAvatarState();
}

class _PetAvatarState extends State<PetAvatar> with TickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: _span,
  )..repeat();

  /// 姿势轮换的进度。一个整圈换完一整轮，不靠定时器：widget 测试里不会留一个没清的 Timer。
  late final AnimationController _pose = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 26000),
  )..repeat();

  /// 一张换到下一张的那一小段，占一格的这么多。
  static const double _fade = 0.07;

  Duration get _span => Duration(
      milliseconds: widget.mood == PetMood.sleeping
          ? 5200
          : (widget.mood.rests ? 3600 : 2000));

  @override
  void didUpdateWidget(PetAvatar old) {
    super.didUpdateWidget(old);
    if (_breathe.duration != _span) {
      _breathe.duration = _span;
      _breathe.repeat();
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    _pose.dispose();
    super.dispose();
  }

  /// 这一次要摆哪几张。当前这一态排在最前面。
  List<PetMood> _poses() {
    final List<PetMood>? wanted = widget.cycle;
    if (wanted != null) {
      if (wanted.isEmpty) return const <PetMood>[];
      return _ordered(wanted);
    }
    // 小尺寸只画一张：24 像素上换姿势既看不出来又浪费一次解码。
    if (widget.size < 72 || !widget.mood.rests) return const <PetMood>[];
    return _ordered(kPetResting);
  }

  List<PetMood> _ordered(List<PetMood> list) => <PetMood>[
        widget.mood,
        ...list.where((PetMood m) => m != widget.mood),
      ];

  @override
  Widget build(BuildContext context) {
    final bool quiet =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    final List<PetMood> poses = quiet ? const <PetMood>[] : _poses();
    Widget body = poses.length > 1
        ? _rotating(poses)
        : _figure(poses.isEmpty ? widget.mood : poses.first);
    if (!quiet) body = _breathing(body);
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

  /// 很轻地呼吸：待机和睡觉一两像素，动手的时候多抬一点。
  Widget _breathing(Widget child) {
    return AnimatedBuilder(
      animation: _breathe,
      builder: (BuildContext ctx, Widget? kid) {
        final double t = _breathe.value * 2 * math.pi;
        final double lift = widget.mood.rests || widget.mood == PetMood.sleeping
            ? math.sin(t) * 1.2
            : math.sin(t) * 2.2;
        final double scale =
            1 + (widget.mood == PetMood.sleeping ? 0.006 : 0.012) * math.sin(t);
        return Transform.translate(
          offset: Offset(0, lift),
          child: Transform.scale(scale: scale, child: kid),
        );
      },
      child: child,
    );
  }

  /// 姿势轮换：一格一格换过去，交界处叠着淡进去，不是硬切。
  Widget _rotating(List<PetMood> poses) {
    return AnimatedBuilder(
      animation: _pose,
      builder: (BuildContext ctx, Widget? child) {
        final double pos = _pose.value * poses.length;
        final double edge = pos - pos.floorToDouble();
        final PetMood cur = poses[pos.floor() % poses.length];
        if (edge >= _fade) return _figure(cur);
        final PetMood prev = poses[(pos.floor() - 1 + poses.length) % poses.length];
        return Stack(
          alignment: Alignment.center,
          children: <Widget>[
            _figure(prev),
            Opacity(opacity: edge / _fade, child: _figure(cur)),
          ],
        );
      },
    );
  }

  Widget _figure(PetMood mood) {
    if (!C.isDark) return _image(mood, widget.size);
    // 立绘是深墨的身子，深色底上会陷进去。垫一块浅底，边上留一点空，像贴纸。
    final double pad = widget.size * 0.08;
    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: C.petPlate,
        borderRadius: BorderRadius.circular(widget.size * 0.16),
      ),
      child: _image(mood, widget.size - pad * 2),
    );
  }

  Widget _image(PetMood mood, double height) {
    return SizedBox(
      height: height,
      child: Image.asset(
        mood.asset,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        // 小的那几处按目标尺寸解码，省下来的内存比清晰度值。
        cacheWidth: widget.size < 200 ? (widget.size * 2).round() : null,
        errorBuilder: (BuildContext ctx, Object error, StackTrace? stack) => SizedBox(
          height: height,
          width: height,
          child: Center(
            child: Icon(Icons.hexagon, size: height * 0.5, color: C.blue),
          ),
        ),
      ),
    );
  }
}
