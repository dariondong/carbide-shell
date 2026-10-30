import 'package:carbide_shell/core/conversation.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 三轮：看磁盘 → 92%，清一下 → 好，再看看 → 干净了。
  List<LlmMessage> path() => <LlmMessage>[
        LlmMessage.user('看磁盘', at: DateTime(2026, 10, 30, 10)),
        const LlmMessage.assistant('92%'),
        LlmMessage.user('清一下', at: DateTime(2026, 10, 30, 10, 5)),
        const LlmMessage.assistant('好'),
        LlmMessage.user('再看看', at: DateTime(2026, 10, 30, 10, 10)),
        const LlmMessage.assistant('干净了'),
      ];

  group('对话的线路图', () {
    test('一轮一格，还没有分支的时候是一条直到底的线', () {
      final List<TreeNode> t = buildTree(path(), const <ConvBranch>[]);
      layoutTree(t);
      expect(t.length, 3);
      expect(t.first.parent, isNull);
      expect(t.last.parent, 1);
      expect(t.first.depth, 0);
      expect(t.last.depth, 2);
      expect(t.first.round, 1);
      expect(t.last.round, 3);
      expect(treeDepth(t), 2);
      expect(treeLanes(t), 1);
      for (final TreeNode n in t) {
        expect(n.lane, 0);
      }
      // 格子上是那句提问本身，不是回答。
      expect(t.first.pathIndex, 0);
      expect(t[1].pathIndex, 2);
      expect(t.last.pathIndex, 4);
      expect(t.first.text, '看磁盘');
    });

    test('退掉的一段从岔口拐到右边一列，主干还在原来那列', () {
      final List<LlmMessage> p = path();
      final ConvBranch b = ConvBranch(
        anchor: 2,
        at: DateTime(2026, 10, 30, 11),
        label: '清一下',
        messages: p.sublist(2),
      );
      // 主线只留第一轮：后面两轮的原文挂在分支上。
      final List<TreeNode> t = buildTree(p.sublist(0, 2), <ConvBranch>[b]);
      layoutTree(t);
      expect(t.length, 3);
      expect(t[1].onPath, isFalse);
      expect(t[1].parent, 0);
      expect(t[1].lane, 1);
      expect(t[1].depth, 1);
      expect(t[1].text, '清一下');
      expect(t.last.text, '再看看');
      expect(t.last.parent, t[1].id);
      // 支线自己接着往下走，不再往右开新列。
      expect(t.last.lane, 1);
      expect(treeLanes(t), 2);
      expect(treeDepth(t), 2);
    });

    test('主线没断的时候，同一轮的另一个说法另起一列', () {
      final List<LlmMessage> p = path();
      final ConvBranch b = ConvBranch(
        anchor: 2,
        at: DateTime(2026, 10, 30, 11),
        label: '清一下',
        messages: p.sublist(2),
      );
      final List<TreeNode> t = buildTree(p, <ConvBranch>[b]);
      layoutTree(t);
      final TreeNode trunkTip = t.where((TreeNode n) => n.onPath).last;
      final TreeNode forkTip = t.where((TreeNode n) => !n.onPath).last;
      expect(trunkTip.lane, 0);
      expect(forkTip.lane, 1);
      expect(treeLanes(t), 2);
    });

    test('分支里连着几轮就串几格，都在同一列', () {
      final ConvBranch b = ConvBranch(
        anchor: 1,
        at: DateTime(2026, 10, 30, 11),
        label: '二',
        messages: <LlmMessage>[
          LlmMessage.user('二', at: DateTime(2026, 10, 30, 11)),
          const LlmMessage.assistant('好'),
          LlmMessage.user('三', at: DateTime(2026, 10, 30, 11, 5)),
          const LlmMessage.assistant('好'),
        ],
      );
      final List<TreeNode> t = buildTree(
        <LlmMessage>[LlmMessage.user('一', at: DateTime(2026, 10, 30, 9))],
        <ConvBranch>[b],
      );
      layoutTree(t);
      expect(t.length, 3);
      expect(t[1].parent, 0);
      expect(t[2].parent, t[1].id);
      expect(t[1].text, '二');
      expect(t[2].text, '三');
      expect(t[1].round, 1);
      expect(t[2].round, 2);
      expect(t[1].lane, 1);
      expect(t[2].lane, 1);
      expect(t[2].depth, 2);
      expect(treeDepth(t), 2);
    });

    test('从最开头分出去的那一叉占满第一列', () {
      final List<LlmMessage> p = path();
      final ConvBranch b = ConvBranch(
        anchor: 0,
        at: DateTime(2026, 10, 30, 11),
        label: '看磁盘',
        messages: p,
      );
      final List<TreeNode> t = buildTree(const <LlmMessage>[], <ConvBranch>[b]);
      layoutTree(t);
      expect(t.length, 3);
      expect(t.first.parent, isNull);
      expect(t.first.depth, 0);
      expect(t[1].parent, 0);
      expect(t[1].depth, 1);
      expect(t.last.depth, 2);
      expect(treeLanes(t), 1);
      for (final TreeNode n in t) {
        expect(n.lane, 0);
      }
    });

    test('一条记录都没有也不会崩', () {
      final List<TreeNode> t = buildTree(const <LlmMessage>[], const <ConvBranch>[]);
      layoutTree(t);
      expect(t, isEmpty);
      expect(treeDepth(t), 0);
      expect(treeLanes(t), 1);
    });

    test('两个分支各占一列，谁也不压在谁身上', () {
      final List<LlmMessage> p = path();
      final ConvBranch a = ConvBranch(
        anchor: 2,
        at: DateTime(2026, 10, 30, 11),
        label: '清一下',
        messages: p.sublist(2),
      );
      final ConvBranch b = ConvBranch(
        anchor: 2,
        at: DateTime(2026, 10, 30, 12),
        label: '别清了',
        messages: <LlmMessage>[
          LlmMessage.user('别清了', at: DateTime(2026, 10, 30, 12)),
        ],
      );
      final List<TreeNode> t = buildTree(p, <ConvBranch>[a, b]);
      layoutTree(t);
      final Set<int> lanes = <int>{
        t.where((TreeNode n) => n.onPath).last.lane,
        t.where((TreeNode n) => n.branch == 0).last.lane,
        t.where((TreeNode n) => n.branch == 1).last.lane,
      };
      expect(lanes.length, 3);
      expect(treeLanes(t), 3);
    });
  });
}
