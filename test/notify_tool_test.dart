import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/tools/notify_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  group('notify', () {
    test('没写正文就不发', () async {
      final ToolOutcome out =
          await NotifyTool().run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('text'));
    });

    test('平台发不出去时如实说，不假装发过', () async {
      final ToolOutcome out = await NotifyTool()
          .run(<String, Object?>{'title': '备份', 'text': '跑完了'}, _ctx);
      if (Platform.isAndroid) {
        // 安卓真机上要么真发出去，要么说清楚为什么没发。
        expect(out.ok || out.error.isNotEmpty, isTrue);
      } else {
        expect(out.ok, isFalse);
        expect(out.error, contains('安卓'));
      }
    });

    test('审批卡上念得出弹的是什么', () {
      final String text = NotifyTool().summarize(
          <String, Object?>{'title': '备份', 'text': '跑完了'});
      expect(text, contains('备份'));
      expect(text, contains('跑完了'));
    });
  });
}
