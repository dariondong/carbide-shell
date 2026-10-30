import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/conversation.dart';
import '../core/models.dart';
import '../core/tree.dart';
import 'theme.dart';

/// 一场对话的线路图。
///
/// 从上往下：一格一轮，主干在左边一列笔直往下走，退掉的每一段从岔口往右拐一条线，
/// 自己再往下走。线条是直角加圆角的，跟电路图一个样子。
class ConvTreePanel extends StatefulWidget {
  const ConvTreePanel({
    super.key,
    required this.messages,
    required this.branches,
    required this.onAct,
    this.height = 320,
  });

  final List<LlmMessage> messages;
  final List<ConvBranch> branches;
  final void Function(TreeNode node) onAct;

  /// 画布多高，超过就上下滚。
  final double height;

  @override
  State<ConvTreePanel> createState() => _ConvTreePanelState();
}

class _ConvTreePanelState extends State<ConvTreePanel> {
  static const double _boxW = 132;
  static const double _boxH = 52;
  static const double _gapY = 26;
  static const double _gapX = 22;
  static const double _pad = 14;

  final ScrollController _down = ScrollController();
  final ScrollController _across = ScrollController();

  late List<TreeNode> _nodes = _build();
  int? _picked;

  List<TreeNode> _build() {
    final List<TreeNode> nodes = buildTree(widget.messages, widget.branches);
    layoutTree(nodes);
    return nodes;
  }

  @override
  void initState() {
    super.initState();
    // 新的一轮在最下面：打开就到底。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_down.hasClients) return;
      _down.jumpTo(_down.position.maxScrollExtent);
    });
  }

  @override
  void dispose() {
    _down.dispose();
    _across.dispose();
    super.dispose();
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

  double get _width {
    final int lanes = treeLanes(_nodes);
    return _pad * 2 + lanes * _boxW + (lanes - 1) * _gapX;
  }

  double get _height {
    final int rows = treeDepth(_nodes) + 1;
    return _pad * 2 + rows * _boxH + (rows - 1) * _gapY;
  }

  Offset _topLeft(TreeNode n) => Offset(
        _pad + n.lane * (_boxW + _gapX),
        _pad + n.depth * (_boxH + _gapY),
      );

  TreeNode? get _node {
    final int? id = _picked;
    if (id == null) return null;
    for (final TreeNode n in _nodes) {
      if (n.id == id) return n;
    }
    return null;
  }

  /// 主线最新那一轮：格子上点一个蓝点。
  TreeNode? get _latest {
    TreeNode? hit;
    for (final TreeNode n in _nodes) {
      if (n.onPath) hit = n;
    }
    return hit;
  }

  static String _stamp(DateTime? t) {
    if (t == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}';
  }

  static String _line(String text) {
    final String one = text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (one.isEmpty) return '（只带了文件）';
    return one.length > 90 ? '${one.substring(0, 90)}…' : one;
  }

  @override
  Widget build(BuildContext context) {
    final TreeNode? n = _node;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: widget.height,
          child: SingleChildScrollView(
            controller: _down,
            child: SingleChildScrollView(
              controller: _across,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _width,
                height: _height,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _WirePainter(
                          nodes: _nodes,
                          topLeft: _topLeft,
                          boxW: _boxW,
                          boxH: _boxH,
                          picked: _picked,
                        ),
                      ),
                    ),
                    for (final TreeNode node in _nodes)
                      Positioned(
                        left: _topLeft(node).dx,
                        top: _topLeft(node).dy,
                        width: _boxW,
                        height: _boxH,
                        child: _box(node),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (n == null)
          Text('点一格：主干上是那一轮，拐到右边去的是退掉的一段。',
              style: C.monoSmall.copyWith(fontSize: 11, color: C.grey2))
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
            decoration: BoxDecoration(
              color: C.paper2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '第 ${n.round} 轮${_stamp(n.at).isEmpty ? '' : ' · ${_stamp(n.at)}'}' +
                      (n.onPath ? '' : ' · 退掉的一段'),
                  style: C.monoSmall.copyWith(
                    fontSize: 10,
                    letterSpacing: 0.6,
                    color: n.onPath ? C.grey2 : C.blue,
                  ),
                ),
                const SizedBox(height: 5),
                Text(_line(n.text),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.55, color: C.ink)),
                const SizedBox(height: 11),
                _actButton(n),
              ],
            ),
          ),
      ],
    );
  }

  /// 一个圆角实心按钮，比方形那颗软和些。
  Widget _actButton(TreeNode n) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: Material(
        color: C.blue,
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => widget.onAct(n),
          child: Center(
            child: Text(
              n.onPath ? '从这一轮重来' : '接回这一段',
              style: TextStyle(
                color: C.onAccent,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _box(TreeNode n) {
    final bool picked = n.id == _picked;
    final bool newest = _latest?.id == n.id;
    final Color fill = picked
        ? C.blueSoft
        : (n.onPath ? C.card : C.blueSoft.withValues(alpha: 0.55));
    return GestureDetector(
      onTap: () => setState(() => _picked = n.id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: picked ? Border.all(color: C.blue, width: 1.3) : null,
          boxShadow: picked ? C.softShadow : (n.onPath ? C.softShadow : null),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (newest && !picked)
                  Container(
                    width: 5,
                    height: 5,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: C.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                Expanded(
                  child: Text(
                    n.onPath ? '第 ${n.round} 轮' : '退掉 · 第 ${n.round} 轮',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: C.monoSmall.copyWith(
                      fontSize: 9,
                      letterSpacing: 0.8,
                      color: n.onPath ? C.grey2 : C.blue,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Expanded(
              child: Text(
                _line(n.text),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  color: n.onPath ? C.ink : C.ink.withValues(alpha: 0.82),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 连线：主干一根竖线往下，岔口拐直角出到右边那一列，再竖直往下进格子。
class _WirePainter extends CustomPainter {
  _WirePainter({
    required this.nodes,
    required this.topLeft,
    required this.boxW,
    required this.boxH,
    required this.picked,
  });

  final List<TreeNode> nodes;
  final Offset Function(TreeNode node) topLeft;
  final double boxW;
  final double boxH;
  final int? picked;

  @override
  void paint(Canvas canvas, Size size) {
    // 先画线，再画岔口的接点。
    for (final TreeNode n in nodes) {
      final int? p = n.parent;
      if (p == null || p < 0 || p >= nodes.length) continue;
      final TreeNode par = nodes[p];
      final Offset from = topLeft(par) + Offset(boxW / 2, boxH);
      final Offset to = topLeft(n) + Offset(boxW / 2, 0);
      final Paint paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = n.onPath ? 1.3 : 1.2
        ..strokeCap = StrokeCap.round
        ..color =
            n.onPath ? C.ink.withValues(alpha: 0.22) : C.blue.withValues(alpha: 0.42);
      canvas.drawPath(_wire(from, to), paint);
    }
    for (final TreeNode n in nodes) {
      // 岔口的接点：有两条以上出口的地方点一个实心小圆。
      int kids = 0;
      for (final TreeNode other in nodes) {
        if (other.parent == n.id) kids += 1;
      }
      if (kids < 2) continue;
      final Offset at = topLeft(n) + Offset(boxW / 2, boxH);
      canvas.drawCircle(at, 2.2, Paint()..color = C.ink.withValues(alpha: 0.32));
    }
    if (picked != null) {
      for (final TreeNode n in nodes) {
        if (n.id != picked) continue;
        canvas.drawCircle(
          topLeft(n) + Offset(boxW / 2, boxH),
          2.2,
          Paint()..color = C.blue,
        );
      }
    }
  }

  /// 直角拐弯，拐角带一点圆弧。
  Path _wire(Offset a, Offset b) {
    final Path path = Path();
    if ((a.dx - b.dx).abs() < 0.5) {
      path.moveTo(a.dx, a.dy);
      path.lineTo(b.dx, b.dy);
      return path;
    }
    final double midY = (a.dy + b.dy) / 2;
    final double dir = b.dx > a.dx ? 1 : -1;
    final double r = math.min(
      14,
      math.min((b.dx - a.dx).abs() / 2, (midY - a.dy).abs().clamp(0, 14)),
    );
    path.moveTo(a.dx, a.dy);
    path.lineTo(a.dx, midY - r);
    path.quadraticBezierTo(a.dx, midY, a.dx + dir * r, midY);
    path.lineTo(b.dx - dir * r, midY);
    path.quadraticBezierTo(b.dx, midY, b.dx, midY + r);
    path.lineTo(b.dx, b.dy);
    return path;
  }

  @override
  bool shouldRepaint(_WirePainter old) =>
      old.picked != picked || old.nodes.length != nodes.length;
}
