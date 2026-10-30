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

  /// 第几列：离根几层。
  int depth = 0;

  /// 第几条线：主干占第 0 条，分出去的每一叉往右开一条。
  int lane = 0;
}

/// 把主线加挂着的分支拼成一棵树：主线是主干，退掉的每一段从分出去的地方岔开。
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

/// 排位置：一行一轮，一列一条线。
///
/// 从上往下：第一个孩子接自己这条线直着往下走，所以主干是一根笔直的竖线；
/// 其余的孩子各往右开一条新线，从岔口拐出去再往下。
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

  int nextLane = 0;
  void assign(int id, int lane) {
    nodes[id].lane = lane;
    final List<int> ch = kids[id] ?? const <int>[];
    for (final int k in ch) {
      // 同一条线接着走就留在这一列；开一条新支线就拐到右边新的一列。
      assign(k, nodes[k].branch == nodes[id].branch ? lane : nextLane++);
    }
  }

  for (final int r in roots) {
    // 先把这一列的号占下来，分支才不会跟主干抢同一列。
    final int lane = nextLane;
    nextLane += 1;
    assign(r, lane);
  }
}

/// 树上一共几层，也就是画出来有几行。
int treeDepth(List<TreeNode> nodes) {
  int max = 0;
  for (final TreeNode n in nodes) {
    if (n.depth > max) max = n.depth;
  }
  return max;
}

/// 树上一共几条线，也就是画出来有几列。
int treeLanes(List<TreeNode> nodes) {
  int max = 0;
  for (final TreeNode n in nodes) {
    if (n.lane > max) max = n.lane;
  }
  return max + 1;
}
