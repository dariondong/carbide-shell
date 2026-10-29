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
    dir = Directory.systemTemp.createTempSync('carbide_mail_to_');
    store = MailStore(File('${dir.path}/mail.json'), MemorySecretStore());
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('允许名单 = 默认收件人 + 额外那几个，去重', () {
    const SmtpConfig config = SmtpConfig(
      to: 'a@example.com, b@example.com',
      allowedTo: <String>['b@example.com', 'ops@example.com'],
    );
    expect(config.recipients, <String>['a@example.com', 'b@example.com']);
    expect(config.allowed,
        <String>['a@example.com', 'b@example.com', 'ops@example.com']);
    expect(config.canSendTo('OPS@example.com'), isTrue);
    expect(config.canSendTo('stranger@example.com'), isFalse);
    expect(config.canSendTo(''), isFalse);
  });

  test('名单跟着 JSON 走', () {
    const SmtpConfig config = SmtpConfig(to: 'a@example.com', allowedTo: <String>['c@example.com']);
    final SmtpConfig back = SmtpConfig.fromJson(config.toJson());
    expect(back.allowed, <String>['a@example.com', 'c@example.com']);
    expect(back.allowedTo, <String>['c@example.com']);
    expect(back.copyWith(to: 'c@example.com').recipients, <String>['c@example.com']);
  });

  test('老版本存下来的一行文本也读得回来', () {
    final SmtpConfig back = SmtpConfig.fromJson(<String, Object?>{
      'to': 'a@example.com',
      'allowedTo': 'c@example.com d@example.com',
    });
    expect(back.allowedTo, <String>['c@example.com', 'd@example.com']);
    expect(back.allowed, <String>['a@example.com', 'c@example.com', 'd@example.com']);
  });

  test('一条地址写成什么算能用', () {
    expect(addressProblem('a@example.com'), isNull);
    expect(addressProblem('  a@example.com  '), isNull);
    expect(addressProblem(''), '没写地址');
    expect(addressProblem('a b@example.com'), contains('空格'));
    expect(addressProblem('aexample.com'), isNotNull);
    expect(addressProblem('a@example'), contains('点'));
  });

  test('AI 选的人不在名单里就不发', () async {
    store.value = const SmtpConfig(
      enabled: true,
      host: 'smtp.example.com',
      from: 'me@example.com',
      to: 'a@example.com',
      allowedTo: <String>['ops@example.com'],
    );
    final ToolOutcome out = await MailSendTool(store).run(
      <String, Object?>{'body': '磁盘满了', 'to': 'stranger@example.com'},
      _ctx,
    );
    expect(out.ok, isFalse);
    expect(out.error, contains('不在允许发送的名单里'));
    expect(out.error, contains('ops@example.com'));
  });

  test('审批卡上写清发给谁、为什么', () {
    final String text = MailSendTool(store).summarize(<String, Object?>{
      'subject': '备份完成',
      'body': '好了',
      'to': 'ops@example.com',
      'why': '他值班',
    });
    expect(text, contains('ops@example.com'));
    expect(text, contains('他值班'));
    expect(text, contains('备份完成'));
  });

  test('发邮件不论档位都先问一句', () {
    expect(MailSendTool(store).alwaysAsk, isTrue);
  });
}
