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
  late MailAllowTool tool;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('carbide_mail_allow_');
    store = MailStore(File('${dir.path}/mail.json'), MemorySecretStore());
    store.value = const SmtpConfig(
      enabled: true,
      host: 'smtp.example.com',
      from: 'me@example.com',
      to: 'a@example.com',
      allowedTo: <String>['ops@example.com'],
    );
    tool = MailAllowTool(store);
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('看清单是只读，加和删一定要问一句', () {
    expect(tool.classify(<String, Object?>{'action': 'list'}), ToolRisk.read);
    expect(tool.asksAlways(<String, Object?>{'action': 'list'}), isFalse);
    for (final String action in <String>['add', 'remove']) {
      final Map<String, Object?> args = <String, Object?>{'action': action, 'address': 'x@y.com'};
      expect(tool.classify(args), ToolRisk.write);
      expect(tool.asksAlways(args), isTrue);
    }
  });

  test('清单里默认收件人写在前面并标出来', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{'action': 'list'}, _ctx);
    expect(out.ok, isTrue);
    expect(out.stdout, contains('a@example.com（默认收件人）'));
    expect(out.stdout, contains('ops@example.com'));
  });

  test('加一个地址：存进文件，下一次能发给它', () async {
    final ToolOutcome out = await tool.run(
      <String, Object?>{'action': 'add', 'address': 'night@example.com'},
      _ctx,
    );
    expect(out.ok, isTrue);
    expect(store.value.canSendTo('night@example.com'), isTrue);
    expect(store.value.allowedTo, <String>['ops@example.com', 'night@example.com']);
    // 落过一次盘：重开一份读回来还在
    final MailStore again = MailStore(File('${dir.path}/mail.json'), MemorySecretStore());
    await again.load();
    expect(again.value.allowedTo, <String>['ops@example.com', 'night@example.com']);
  });

  test('加过的再加一次：不重复，也不算错', () async {
    await tool.run(<String, Object?>{'action': 'add', 'address': 'NIGHT@example.com'}, _ctx);
    final ToolOutcome out = await tool.run(
      <String, Object?>{'action': 'add', 'address': 'night@example.com'},
      _ctx,
    );
    expect(out.ok, isTrue);
    expect(out.stdout, contains('已经能发'));
    // 名单里原本那条 ops 还在，只多了第一次加进去的那一个
    expect(store.value.allowedTo.length, 2);
    expect(
      store.value.allowedTo.where((String e) => e.toLowerCase() == 'night@example.com').length,
      1,
    );
  });

  test('写坏的地址不动名单', () async {
    final ToolOutcome out = await tool.run(
      <String, Object?>{'action': 'add', 'address': 'night@example'},
      _ctx,
    );
    expect(out.ok, isFalse);
    expect(out.error, contains('点'));
    expect(store.value.allowedTo, <String>['ops@example.com']);
  });

  test('删一个地址；删不掉的默认收件人给一句人话', () async {
    final ToolOutcome gone = await tool.run(
      <String, Object?>{'action': 'remove', 'address': 'ops@example.com'},
      _ctx,
    );
    expect(gone.ok, isTrue);
    expect(store.value.canSendTo('ops@example.com'), isFalse);

    final ToolOutcome fixed =
        await tool.run(<String, Object?>{'action': 'remove', 'address': 'a@example.com'}, _ctx);
    expect(fixed.ok, isFalse);
    expect(fixed.error, contains('默认收件人'));
    expect(store.value.canSendTo('a@example.com'), isTrue);
  });

  test('同名删两次：第二次说名单里没有', () async {
    await tool.run(<String, Object?>{'action': 'remove', 'address': 'ops@example.com'}, _ctx);
    final ToolOutcome again = await tool.run(
      <String, Object?>{'action': 'remove', 'address': 'ops@example.com'},
      _ctx,
    );
    expect(again.ok, isFalse);
    expect(again.error, contains('没有'));
  });

  test('改名单会通知界面刷新', () async {
    int seen = 0;
    void watch() => seen += 1;
    store.addListener(watch);
    await tool.run(<String, Object?>{'action': 'add', 'address': 'night@example.com'}, _ctx);
    store.removeListener(watch);
    expect(seen, greaterThan(0));
  });
}
