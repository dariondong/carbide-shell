import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/smtp.dart';
import 'package:carbide_shell/data/mail.dart';
import 'package:carbide_shell/data/secrets.dart';
import 'package:carbide_shell/tools/mail_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  late Directory dir;
  late MailStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('carbide_mail_');
    store = MailStore(File('${dir.path}/mail.json'), MemorySecretStore());
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('mail_send', () {
    test('没写正文就不发', () async {
      final ToolOutcome out =
          await MailSendTool(store).run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('body'));
    });

    test('邮箱没打开时如实说', () async {
      final ToolOutcome out = await MailSendTool(store)
          .run(<String, Object?>{'body': '磁盘满了'}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('没打开'));
    });

    test('差哪一项也说得出来', () async {
      store.value =
          const SmtpConfig(enabled: true, host: 'smtp.example.com', to: 'a@example.com');
      final ToolOutcome out = await MailSendTool(store)
          .run(<String, Object?>{'body': '磁盘满了'}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('没填发件人'));
    });

    test('审批卡上念得出主题', () {
      final String text = MailSendTool(store)
          .summarize(<String, Object?>{'subject': '备份完成', 'body': '好了'});
      expect(text, contains('备份完成'));
    });
  });
}
