import 'dart:io';

import 'package:carbide_shell/core/conversation.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/data/hosts.dart';
import 'package:carbide_shell/data/secrets.dart';
import 'package:carbide_shell/tools/host_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late HostStore hosts;
  late MemorySecretStore secrets;
  late AddHostTool tool;
  late ToolContext context;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('carbide_hosts');
    hosts = HostStore(File('${dir.path}/hosts.json'));
    await hosts.load();
    secrets = MemorySecretStore();
    tool = AddHostTool(hosts: hosts, secrets: secrets);
    context = ToolContext(workspace: dir.path, desktop: false);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('加一台：主机进列表，密码进密钥库', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{
      'name': 'web-01',
      'host': '10.0.0.21',
      'user': 'deploy',
      'secret': 'hunter2',
    }, context);
    expect(out.ok, isTrue, reason: out.error);
    expect(out.stdout.contains('web-01'), isTrue);

    final HostEntry entry = hosts.hosts.single;
    expect(entry.name, 'web-01');
    expect(entry.host, '10.0.0.21');
    expect(entry.port, 22);
    expect(entry.user, 'deploy');
    expect(entry.auth, 'password');
    expect(await secrets.read(hostSecretKey(entry.id)), 'hunter2');

    // 落盘了才算数：换一个 store 从文件读回来。
    final HostStore reread = HostStore(File('${dir.path}/hosts.json'));
    await reread.load();
    expect(reread.hosts.single.name, 'web-01');
  });

  test('私钥那种写 key，端口可以指定', () async {
    final ToolOutcome out = await tool.run(<String, Object?>{
      'name': 'db',
      'host': '10.0.0.22',
      'port': 2222,
      'user': 'root',
      'auth': 'key',
      'secret': '-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END-----',
    }, context);
    expect(out.ok, isTrue, reason: out.error);
    final HostEntry entry = hosts.hosts.single;
    expect(entry.port, 2222);
    expect(entry.auth, 'key');
  });

  test('同名不给加', () async {
    await hosts.upsert(HostEntry(id: 'h1', name: 'web-01', host: '10.0.0.21'));
    final ToolOutcome out = await tool.run(<String, Object?>{
      'name': 'web-01',
      'host': '10.0.0.99',
      'secret': 'x',
    }, context);
    expect(out.ok, isFalse);
    expect(out.error.contains('已经有一台叫 web-01'), isTrue);
    expect(hosts.hosts.length, 1);
  });

  test('缺密钥、端口不对都不加', () async {
    final ToolOutcome noSecret = await tool.run(<String, Object?>{
      'name': 'x',
      'host': '10.0.0.5',
    }, context);
    expect(noSecret.ok, isFalse);
    expect(noSecret.error.contains('密码或私钥'), isTrue);

    final ToolOutcome badPort = await tool.run(<String, Object?>{
      'name': 'x',
      'host': '10.0.0.5',
      'port': 70000,
      'secret': 'y',
    }, context);
    expect(badPort.ok, isFalse);
    expect(hosts.hosts, isEmpty);
  });

  test('审批卡上那行说清楚加什么', () {
    expect(
      tool.summarize(<String, Object?>{
        'name': 'web-01',
        'host': '10.0.0.21',
        'user': 'deploy',
        'secret': 'x',
      }),
      '加主机 web-01 = deploy@10.0.0.21:22（密码）',
    );
    expect(
      tool.summarize(<String, Object?>{
        'name': 'db',
        'host': '10.0.0.22',
        'port': 2222,
        'auth': 'key',
        'secret': 'x',
      }),
      '加主机 db = root@10.0.0.22:2222（私钥）',
    );
    expect(tool.classify(<String, Object?>{}), ToolRisk.write);
  });

  group('Advance Master 记在对话上', () {
    test('写进 json 再读回来', () {
      final Conversation c = Conversation(id: 'c1', title: 't', hostId: '')
        ..advanceMaster = true;
      final Map<String, Object?> json = c.toJson();
      expect(json['advanceMaster'], true);
      expect(Conversation.fromJson(json).advanceMaster, isTrue);
      expect(Conversation(id: 'c2', title: 't', hostId: '').toJson().containsKey('advanceMaster'),
          isFalse);
    });

    test('开了就是全部主机，范围参数被忽略', () async {
      final ConversationStore store = ConversationStore(Directory('${dir.path}/talks'));
      await store.load();
      final Conversation c =
          await store.create(title: '总控', hostId: 'h1', advanceMaster: true);
      expect(c.advanceMaster, isTrue);
      expect(c.hostId, '');
      expect(c.multiHost, isTrue);
    });
  });
}
