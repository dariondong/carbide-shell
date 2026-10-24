import 'dart:io';

import 'package:carbide_shell/core/conversation.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('carbide_conv');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('对话能存能读，工具调用和结果都留着', () async {
    final ConversationStore store = ConversationStore(dir);
    await store.load();
    final Conversation c = await store.create(title: '磁盘清理', hostId: '');
    c.messages.add(const LlmMessage.user('看看磁盘'));
    c.messages.add(const LlmMessage.assistant('先看一眼', calls: <LlmToolCall>[
      LlmToolCall(id: 'c1', name: 'ssh_exec', args: <String, Object?>{'command': 'df -h'}),
    ]));
    c.messages.add(const LlmMessage.toolResult(
      text: 'ok', toolCallId: 'c1', toolName: 'ssh_exec'));
    await store.save(c);

    final ConversationStore again = ConversationStore(dir);
    await again.load();
    final Conversation back = again.all.first;
    expect(back.title, '磁盘清理');
    expect(back.messages.length, 3);
    expect(back.messages[1].calls.first.name, 'ssh_exec');
    expect(back.messages[2].toolCallId, 'c1');
    expect(back.turns, 1);
  });

  test('单机对话的 scope 是主机 id，多机是 global', () async {
    final ConversationStore store = ConversationStore(dir);
    await store.load();
    final Conversation single = await store.create(title: 'a', hostId: 'h1');
    final Conversation multi = await store.create(title: 'b');
    expect(single.scope, 'h1');
    expect(multi.scope, 'global');
    expect(single.multiHost, isFalse);
  });

  test('放过一类命令之后同类不再问，重启也记得', () async {
    final ConversationStore store = ConversationStore(dir);
    await store.load();
    final Conversation c = await store.create(title: 'a', hostId: '');
    expect(c.allowsKind('ssh_exec:df'), isFalse);
    c.kindApprovals.add('ssh_exec:df');
    await store.save(c);

    final ConversationStore again = ConversationStore(dir);
    await again.load();
    expect(again.all.first.allowsKind('ssh_exec:df'), isTrue);
    expect(again.all.first.allowsKind('ssh_exec:rm'), isFalse);
  });

  test('整个对话放开之后所有类都放行', () async {
    final Conversation c = Conversation(id: 'x', title: 't', hostId: '');
    c.autoApproveAll = true;
    expect(c.allowsKind('ssh_exec:rm'), isTrue);
    expect(c.allowsKind('ssh_sftp:write'), isTrue);
  });

  test('删掉对话连记录文件一起没', () async {
    final ConversationStore store = ConversationStore(dir);
    await store.load();
    final Conversation c = await store.create(title: 'a');
    expect(File('${dir.path}/${c.id}.json').existsSync(), isTrue);
    await store.remove(c.id);
    expect(File('${dir.path}/${c.id}.json').existsSync(), isFalse);
    expect(store.all, isEmpty);
  });
}
