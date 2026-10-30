import 'dart:math' as math;

import 'package:carbide_shell/core/conversation.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/tree.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// 两轮：看磁盘 → 92%，清一下 → 好。
  List<LlmMessage> path() => <LlmMessage>[
        LlmMessage.user('看磁盘', at: DateTime(2026, 10, 30, 10)),
        const LlmMessage.assistant('92%'),
        LlmMessage.user('清一下', at: DateTime(2026, 10, 30, 10, 5)),
        const LlmMessage.assistant('好'),
      ];

  group('对话的树', () {
    test('一轮一个点，还没有分支的时候就是一根直线', () {
      final List<TreeNode> t = buildTree(path(), const <ConvBranch>[]);
      layoutTree(t);
      expect(t.length, 2);
      expect(t.first.parent, isNull);
      expect(t.last.parent, 0);
      expect(t.first.depth, 0);
      expect(t.last.depth, 1);
      expect(t.first.round, 1);
      expect(t.last.round, 2);
      expect(treeDepth(t), 1);
      expect(t.last.angle, closeTo(t.first.angle, 1e-9));
      // 点上是那句提问本身，不是回答。
      expect(t.first.pathIndex, 0);
      expect(t.last.pathIndex, 2);
      expect(t.first.text, '看磁盘');
    });

    test('退掉的一段从上一轮长出去，挂在树上', () {
      final List<LlmMessage> p = path();
      final ConvBranch b = ConvBranch(
        anchor: 2,
        at: DateTime(2026, 10, 30, 11),
        label: '清一下',
        messages: p.sublist(2),
      );
      // 只留第一轮：第二轮的原文挂在分支上。
      final List<TreeNode> t = buildTree(p.sublist(0, 2), <ConvBranch>[b]);
      layoutTree(t);
      final TreeNode fork = t.last;
      expect(fork.onPath, isFalse);
      expect(fork.parent, 0);
      expect(fork.branch, 0);
      expect(fork.round, 1);
      expect(fork.depth, 1);
      expect(treeDepth(t), 1);
    });

    test('分支里连着几轮就串几节', () {
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
      final TreeNode two = t[1];
      final TreeNode three = t[2];
      expect(two.parent, 0);
      expect(three.parent, two.id);
      expect(two.text, '二');
      expect(three.text, '三');
      expect(two.round, 1);
      expect(three.round, 2);
      expect(three.depth, 2);
      expect(treeDepth(t), 2);
    });

    test('分出去之后，两条线的角度不再一样', () {
      final List<LlmMessage> p = path();
      final ConvBranch b = ConvBranch(
        anchor: 2,
        at: DateTime(2026, 10, 30, 11),
        label: '清一下',
        messages: p.sublist(2),
      );
      // 主线没截断：同一轮的另一个说法挂在树上，分叉点上真的长出两个叉。
      final List<TreeNode> t = buildTree(p, <ConvBranch>[b]);
      layoutTree(t);
      final TreeNode trunkTip = t.last;
      final TreeNode forkTip = t.where((TreeNode n) => !n.onPath).last;
      expect(trunkTip.angle, isNot(closeTo(forkTip.angle, 1e-6)));
      expect(forkTip.angle.isFinite, isTrue);
      expect(forkTip.angle.abs(), lessThanOrEqualTo(math.pi + 1e-9));
    });

    test('从最开头分出去的那一叉挂在根上', () {
      final List<LlmMessage> p = path();
      final ConvBranch b = ConvBranch(
        anchor: 0,
        at: DateTime(2026, 10, 30, 11),
        label: '看磁盘',
        messages: p,
      );
      final List<TreeNode> t = buildTree(const <LlmMessage>[], <ConvBranch>[b]);
      layoutTree(t);
      expect(t.length, 2);
      expect(t.first.parent, isNull);
      expect(t.first.depth, 0);
      expect(t.last.parent, 0);
      expect(t.last.depth, 1);
    });

    test('一条记录都没有也不会崩', () {
      final List<TreeNode> t = buildTree(const <LlmMessage>[], const <ConvBranch>[]);
      layoutTree(t);
      expect(t, isEmpty);
      expect(treeDepth(t), 0);
    });

    test('两个分支各自占一个角，谁也不压在谁身上', () {
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
      final List<TreeNode> tips = <TreeNode>[
        t.last,
        t.where((TreeNode n) => n.branch == 0).last,
        t.where((TreeNode n) => n.branch == 1).last,
      ];
      expect(tips.map((TreeNode n) => n.angle.toStringAsFixed(4)).toSet().length, 3);
    });
  });
}
