import 'dart:math' as math;

import 'conversation.dart';
import 'models.dart';

/// 树上的一节：一轮对话。
///
/// 一轮 = 那句提问和它后面的回答、工具结果，一直到下一句提问为止。
/// 每个节点只有一个父亲，所以一场对话连同退掉的几段真的是一棵树。
class TreeNode {
  TreeNode({
    required this.id,
    required this.parent,
    required this.text,
    required this.at,
    required this.pathIndex,
    required this.branch,
    required this.round,
  });

  final int id;
  final int? parent;

  /// 这一轮的那句提问。
  final String text;
  final DateTime? at;

  /// 主线上时，这句提问在 `messages` 里的下标；不在主线上是 -1。
  final int pathIndex;

  /// 挂在哪个分支上（`branches` 的下标），主线是 -1。
  final int branch;

  /// 这条路上第几轮，从 1 数。
  final int round;

  bool get onPath => pathIndex >= 0;

  /// 离根几层，画的时候决定半径。
  int depth = 0;

  /// 从圆心看过去的角度（弧度）。
  double angle = 0;
}

/// 把主线加挂着的分支拼成一棵树：主线是树干，退掉的每一段从分出去的地方长出来。
List<TreeNode> buildTree(List<LlmMessage> path, List<ConvBranch> branches) {
  final List<TreeNode> nodes = <TreeNode>[];
  int? last;
  int round = 0;
  for (int i = 0; i < path.length; i += 1) {
    final LlmMessage m = path[i];
    if (m.role != LlmRole.user) continue;
    round += 1;
    final TreeNode n = TreeNode(
      id: nodes.length,
      parent: last,
      text: m.text,
      at: m.at,
      pathIndex: i,
      branch: -1,
      round: round,
    );
    nodes.add(n);
    last = n.id;
  }

  for (int b = 0; b < branches.length; b += 1) {
    final ConvBranch br = branches[b];
    // 这一叉从哪儿长出来：主线上最后那一轮提问。
    int? parent;
    if (br.anchor > 0) {
      parent = last;
      for (int i = 0; i < path.length && i < br.anchor; i += 1) {
        if (path[i].role == LlmRole.user) parent = _roundIdAt(nodes, i) ?? parent;
      }
    }
    int round = 0;
    for (int k = 0; k < br.messages.length; k += 1) {
      final LlmMessage m = br.messages[k];
      if (m.role != LlmRole.user) continue;
      round += 1;
      final int id = nodes.length;
      nodes.add(TreeNode(
        id: id,
        parent: parent,
        text: m.text,
        at: m.at,
        pathIndex: -1,
        branch: b,
        round: round,
      ));
      parent = id;
    }
  }
  return nodes;
}

int? _roundIdAt(List<TreeNode> nodes, int pathIndex) {
  for (final TreeNode n in nodes) {
    if (n.pathIndex == pathIndex) return n.id;
  }
  return null;
}

/// 同心圆布局：深度决定半径，叶子平分一整圈，中间的节点取孩子角度的中点。
///
/// 一条链（还没有分支的时候）就是一根笔直的射线；分出几段，就在分叉处掰开几个角。
void layoutTree(List<TreeNode> nodes) {
  if (nodes.isEmpty) return;
  final Map<int, List<int>> kids = <int, List<int>>{};
  final List<int> roots = <int>[];
  for (final TreeNode n in nodes) {
    final int? p = n.parent;
    if (p == null || p < 0 || p >= nodes.length) {
      roots.add(n.id);
      continue;
    }
    kids.putIfAbsent(p, () => <int>[]).add(n.id);
  }

  for (final TreeNode n in nodes) {
    int depth = 0;
    int? p = n.parent;
    int guard = 0;
    while (p != null && p >= 0 && p < nodes.length && guard < nodes.length) {
      depth += 1;
      p = nodes[p].parent;
      guard += 1;
    }
    n.depth = depth;
  }

  int leaves = 0;
  void countLeaves(int id) {
    final List<int> ch = kids[id] ?? const <int>[];
    if (ch.isEmpty) {
      leaves += 1;
      return;
    }
    for (final int k in ch) {
      countLeaves(k);
    }
  }

  for (final int r in roots) {
    countLeaves(r);
  }
  if (leaves <= 0) return;
  final double step = 2 * math.pi / leaves;
  int slot = 0;

  void assign(int id) {
    final List<int> ch = kids[id] ?? const <int>[];
    if (ch.isEmpty) {
      nodes[id].angle = -math.pi / 2 + slot * step;
      slot += 1;
      return;
    }
    for (final int k in ch) {
      assign(k);
    }
    final double first = nodes[ch.first].angle;
    final double last = nodes[ch.last].angle;
    nodes[id].angle = (first + last) / 2;
  }

  for (final int r in roots) {
    assign(r);
  }
}

/// 树上一共几层，画的时候定半径。
int treeDepth(List<TreeNode> nodes) {
  int max = 0;
  for (final TreeNode n in nodes) {
    if (n.depth > max) max = n.depth;
  }
  return max;
}
