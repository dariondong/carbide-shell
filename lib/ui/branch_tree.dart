import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/conversation.dart';
import '../core/models.dart';
import '../core/tree.dart';

import 'components.dart';
import 'theme.dart';

/// 一场对话的树。
///
/// 同心圆：中间是这场对话的起点，往外一圈是一句。主线是一根笔直的射线，
/// 退掉的每一段在它分出去的那一圈掰开一个角，一直长到最外圈。
/// 点一个点先选中，下面写清这是哪一句、能做什么，按按钮才真的动。
class ConvTreePanel extends StatefulWidget {
  const ConvTreePanel({
    super.key,
    required this.messages,
    required this.branches,
    required this.onAct,
    this.side = 300,
  });

  final List<LlmMessage> messages;
  final List<ConvBranch> branches;
  final void Function(TreeNode node) onAct;
  final double side;

  @override
  State<ConvTreePanel> createState() => _ConvTreePanelState();
}

class _ConvTreePanelState extends State<ConvTreePanel> {
  late List<TreeNode> _nodes = _build();
  int? _picked;

  List<TreeNode> _build() {
    final List<TreeNode> nodes = buildTree(widget.messages, widget.branches);
    layoutTree(nodes);
    return nodes;
  }

  @override
  void didUpdateWidget(ConvTreePanel old) {
    super.didUpdateWidget(old);
    if (old.messages.length != widget.messages.length ||
        old.branches.length != widget.branches.length) {
      _nodes = _build();
      _picked = null;
    }
  }

  TreeNode? get _node {
    final int? id = _picked;
    if (id == null) return null;
    for (final TreeNode n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  double get _step {
    final int max = treeDepth(_nodes);
    if (max <= 0) return 0;
    return (widget.side / 2 - 24) / max;
  }

  Offset _at(TreeNode n) {
    final double r = n.depth * _step;
    return Offset(
      widget.side / 2 + math.cos(n.angle) * r,
      widget.side / 2 + math.sin(n.angle) * r,
    );
  }

  void _tap(TapUpDetails d) {
    TreeNode? best;
    double bestD = 20;
    for (final TreeNode n in _nodes) {
      final double dist = (_at(n) - d.localPosition).distance;
      if (dist < bestD) {
        bestD = dist;
        best = n;
      }
    }
    setState(() => _picked = best?.id);
  }

  static String _stamp(DateTime? t) {
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  static String _line(String text) {
    final String one = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (one.isEmpty) return '（这一句只带了文件）';
    return one.length > 60 ? '${one.substring(0, 60)}…' : one;
  }

  @override
  Widget build(BuildContext context) {
    final TreeNode? n = _node;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          width: widget.side,
          height: widget.side,
          child: GestureDetector(
            onTapUp: _tap,
            child: CustomPaint(
              painter: _TreePainter(nodes: _nodes, picked: _picked, step: _step),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (n == null)
          Text('点一个点：主线上的是那一轮，掰到边上的那一串是退掉的一段。',
              style: C.monoSmall.copyWith(fontSize: 11, color: C.grey2))
        else ...<Widget>[
          Text(
            '第 ${n.round} 轮${_stamp(n.at).isEmpty ? '' : ' · ${_stamp(n.at)}'}' +
                (n.onPath ? '' : ' · 退掉的一段'),
            style: C.monoSmall.copyWith(
              fontSize: 10.5,
              color: n.onPath ? C.grey2 : C.blue,
            ),
          ),
          const SizedBox(height: 3),
          Text(_line(n.text),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, height: 1.5, color: C.ink)),
          const SizedBox(height: 8),
          SquareButton(
            label: n.onPath ? '从这一句重来' : '接回这一段',
            filled: true,
            onPressed: () => widget.onAct(n),
          ),
        ],
      ],
    );
  }
}

class _TreePainter extends CustomPainter {
  _TreePainter({required this.nodes, required this.picked, required this.step});

  final List<TreeNode> nodes;
  final int? picked;
  final double step;

  Offset _at(Size size, TreeNode n) {
    final double r = n.depth * step;
    return Offset(
      size.width / 2 + math.cos(n.angle) * r,
      size.height / 2 + math.sin(n.angle) * r,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final int max = treeDepth(nodes);

    // 一圈一圈的同心线：这是坛城的底，也是时间的刻度。
    final Paint ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = C.rule.withValues(alpha: 0.7);
    for (int d = 1; d <= max; d += 1) {
      canvas.drawCircle(center, d * step, ring);
    }

    // 连线：主线一根深色的干，分支用强调色掰出去。
    for (final TreeNode n in nodes) {
      final int? p = n.parent;
      if (p == null || p < 0 || p >= nodes.length) continue;
      final Offset a = _at(size, nodes[p]);
      final Offset b = _at(size, n);
      final Paint line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = n.onPath ? 1.6 : 1.3
        ..color = n.onPath
            ? C.ink.withValues(alpha: 0.35)
            : C.blue.withValues(alpha: 0.55);
      canvas.drawLine(a, b, line);
    }

    // 节点。
    int lastPath = -1;
    for (final TreeNode n in nodes) {
      if (n.pathIndex > lastPath) lastPath = n.pathIndex;
    }
    for (final TreeNode n in nodes) {
      final Offset o = _at(size, n);
      final bool newest = n.onPath && n.pathIndex == lastPath;
      final bool sel = n.id == picked;
      if (sel) {
        canvas.drawCircle(
          o,
          9,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = C.blue,
        );
      }
      if (n.onPath) {
        canvas.drawCircle(
          o,
          newest ? 5 : 3.4,
          Paint()..color = newest ? C.blue : C.ink.withValues(alpha: 0.55),
        );
      } else {
        canvas.drawCircle(
          o,
          3.4,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = C.blue.withValues(alpha: 0.9),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_TreePainter old) =>
      old.picked != picked || old.step != step || old.nodes.length != nodes.length;
}
