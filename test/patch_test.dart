import 'package:carbide_shell/core/patch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('planPatch', () {
    const String conf = '#SystemMaxUse=\nSystemKeepFree=1G\n#SystemMaxFileSize=\n';

    test('只出现一次就换掉', () {
      final PatchPlan plan = planPatch(conf, '#SystemMaxUse=', 'SystemMaxUse=500M');
      expect(plan.ok, isTrue, reason: plan.error);
      expect(plan.text, 'SystemMaxUse=500M\nSystemKeepFree=1G\n#SystemMaxFileSize=\n');
    });

    test('找不到就不改', () {
      final PatchPlan plan = planPatch(conf, 'SystemMaxRetention=', 'x');
      expect(plan.ok, isFalse);
      expect(plan.error, contains('没有这段'));
      expect(plan.text, isEmpty);
    });

    test('改的位置报得出来', () {
      final PatchPlan plan = planPatch(conf, 'SystemKeepFree', 'SystemKeepFree');
      expect(plan.ok, isTrue);
      expect(lineOf(conf, plan.at), 2);
    });

    test('出现两次就拒绝，别猜改哪一处', () {
      final PatchPlan plan = planPatch('a\nb\na\n', 'a', 'z');
      expect(plan.ok, isFalse);
      expect(plan.error, contains('2 次'));
      expect(plan.text, isEmpty);
    });

    test('空字符串直接拒绝', () {
      final PatchPlan plan = planPatch('abc', '', 'x');
      expect(plan.ok, isFalse);
      expect(plan.error, contains('空'));
    });

    test('换成空串等于删掉这一段', () {
      final PatchPlan plan = planPatch('keep\ndrop\nkeep2\n', 'drop\n', '');
      expect(plan.ok, isTrue);
      expect(plan.text, 'keep\nkeep2\n');
    });

    test('前后文不一样的两段不会被搞混', () {
      const String src = '[a]\nx=1\n[b]\nx=1\n';
      final PatchPlan plan = planPatch(src, '[b]\nx=1', '[b]\nx=2');
      expect(plan.ok, isTrue, reason: plan.error);
      expect(plan.text, '[a]\nx=1\n[b]\nx=2\n');
    });

    test('多行 old_string 也对得上', () {
      const String src = 'line1\nline2\nline3\n';
      final PatchPlan plan = planPatch(src, 'line1\nline2', 'one\ntwo');
      expect(plan.ok, isTrue);
      expect(plan.text, 'one\ntwo\nline3\n');
    });
  });
}
