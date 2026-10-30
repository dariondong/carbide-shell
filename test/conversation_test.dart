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

  group('工具调用和结果对齐', () {
    test('好的记录一条不动', () {
      final List<LlmMessage> m = <LlmMessage>[
        const LlmMessage.user('看磁盘'),
        const LlmMessage.assistant('跑一下', calls: <LlmToolCall>[
          LlmToolCall(id: 'c1', name: 'ssh_exec', args: <String, Object?>{}),
        ]),
        const LlmMessage.toolResult(text: 'ok', toolCallId: 'c1', toolName: 'ssh_exec'),
      ];
      expect(repairToolPairs(m), 0);
      expect(m.length, 3);
    });

    test('命令跑到一半退出：缺的结果补成没跑完', () {
      final List<LlmMessage> m = <LlmMessage>[
        const LlmMessage.user('重装一下 nginx'),
        const LlmMessage.assistant('两条命令', calls: <LlmToolCall>[
          LlmToolCall(id: 'c1', name: 'ssh_exec', args: <String, Object?>{}),
          LlmToolCall(id: 'c2', name: 'ssh_exec', args: <String, Object?>{}),
        ]),
        const LlmMessage.toolResult(text: '第一条好了', toolCallId: 'c1', toolName: 'ssh_exec'),
        const LlmMessage.user('好了吗'),
      ];
      expect(repairToolPairs(m), 1);
      expect(m.length, 5);
      expect(m[2].toolCallId, 'c1');
      expect(m[3].toolCallId, 'c2', reason: '缺的那条紧跟在同组结果后面');
      expect(m[3].failed, isTrue);
      expect(m[3].text, contains('没跑完'));
      expect(m[4].text, '好了吗', reason: '后面那句提问不该被挪走');
    });

    test('孤立的工具结果丢掉', () {
      final List<LlmMessage> m = <LlmMessage>[
        const LlmMessage.user('看磁盘'),
        const LlmMessage.toolResult(text: '孤立', toolCallId: 'x9', toolName: 'ssh_exec'),
        const LlmMessage.assistant('看完了'),
      ];
      expect(repairToolPairs(m), 1);
      expect(m.length, 2);
      expect(m.first.role, LlmRole.user);
    });

    test('同一个调用重复的结果只留一条', () {
      final List<LlmMessage> m = <LlmMessage>[
        const LlmMessage.assistant('跑', calls: <LlmToolCall>[
          LlmToolCall(id: 'c1', name: 'ssh_exec', args: <String, Object?>{}),
        ]),
        const LlmMessage.toolResult(text: '一', toolCallId: 'c1', toolName: 'ssh_exec'),
        const LlmMessage.toolResult(text: '二', toolCallId: 'c1', toolName: 'ssh_exec'),
      ];
      expect(repairToolPairs(m), 1);
      expect(m.length, 2);
      expect(m.last.text, '一');
    });

    test('读回来的时候自己修一次', () async {
      final ConversationStore store = ConversationStore(dir);
      await store.load();
      final Conversation c = await store.create(title: '半截', hostId: '');
      c.messages.add(const LlmMessage.user('跑一下'));
      c.messages.add(const LlmMessage.assistant('两条', calls: <LlmToolCall>[
        LlmToolCall(id: 'c1', name: 'ssh_exec', args: <String, Object?>{}),
        LlmToolCall(id: 'c2', name: 'ssh_exec', args: <String, Object?>{}),
      ]));
      c.messages.add(const LlmMessage.toolResult(
          text: 'ok', toolCallId: 'c1', toolName: 'ssh_exec'));
      await store.save(c);

      final ConversationStore again = ConversationStore(dir);
      await again.load();
      final List<LlmMessage> back = again.all.first.messages;
      expect(back.length, 4);
      expect(back.last.role, LlmRole.tool);
      expect(back.last.toolCallId, 'c2');
    });
  });

  group('回退是一棵树', () {
    Conversation fresh(List<LlmMessage> msgs) =>
        Conversation(id: 'c1', title: 't', hostId: 'h', messages: msgs);

    List<LlmMessage> three() => <LlmMessage>[
          LlmMessage.user('看磁盘', at: DateTime(2026, 10, 30, 10)),
          const LlmMessage.assistant('92%'),
          LlmMessage.user('清一下', at: DateTime(2026, 10, 30, 10, 5)),
          const LlmMessage.assistant('好'),
        ];

    test('退掉的那一段挂到树上，一句都不丢', () {
      final Conversation c = fresh(three());
      final ConvBranch? b = c.lift(2);
      expect(b, isNotNull);
      expect(c.messages.length, 2);
      expect(b!.messages.length, 2);
      expect(b.messages.first.text, '清一下');
      expect(b.anchor, 2);
      expect(c.branches.length, 1);
    });

    test('接回来原样回来，树上那一叉就没了', () {
      final Conversation c = fresh(three());
      final ConvBranch b = c.lift(2)!;
      expect(c.restore(b), isNull);
      expect(c.messages.length, 4);
      expect(c.messages.last.text, '好');
      expect(c.branches, isEmpty);
    });

    test('接回来之前手边这一段先挂树上，所以接这一步也能反悔', () {
      final Conversation c = fresh(three());
      final ConvBranch b = c.lift(2)!;
      // 退回去之后又接着聊了两条，再想把原来那段接回来。
      c.messages.add(const LlmMessage.user('换一个问法'));
      c.messages.add(const LlmMessage.assistant('行'));
      final ConvBranch? shelved = c.restore(b);
      expect(shelved, isNotNull);
      expect(shelved!.messages.first.text, '换一个问法');
      expect(c.messages.length, 4);
      expect(c.messages.last.text, '好');
      // 两个叉都在树上：接回来的那段走了，刚接走的这段挂着。
      expect(c.branches.length, 1);
      expect(c.branches.single.messages.length, 2);
    });

    test('记录从头上被收掉几条，锚点跟着挪', () {
      final Conversation c = fresh(three());
      c.lift(2);
      c.messages.add(const LlmMessage.user('又一句'));
      // 前面两条被收掉（太长或者压缩）。
      c.messages.removeRange(0, 2);
      c.shiftBranches(2);
      expect(c.branches.single.anchor, 0);
    });

    test('锚点落在被收掉那一段里的分支就留不住了', () {
      final Conversation c = fresh(three());
      c.lift(1);
      expect(c.branches.length, 1);
      c.shiftBranches(2);
      expect(c.branches, isEmpty);
    });

    test('树存盘读回来还在', () async {
      final ConversationStore store = ConversationStore(dir);
      await store.load();
      final Conversation c = await store.create(title: 'a');
      c.messages.addAll(three());
      c.lift(2);
      await store.save(c);

      final ConversationStore again = ConversationStore(dir);
      await again.load();
      final Conversation back = again.all.first;
      expect(back.messages.length, 2);
      expect(back.branches.length, 1);
      expect(back.branches.single.messages.first.text, '清一下');
      expect(back.branches.single.anchor, 2);
    });
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

  test('存一次不留临时文件，写的是完整一份', () async {
    final ConversationStore store = ConversationStore(dir);
    await store.load();
    final Conversation c = await store.create(title: 'a');
    c.messages.add(const LlmMessage.user('在吗'));
    await store.save(c);
    final List<String> names = dir
        .listSync()
        .whereType<File>()
        .map((File f) => f.uri.pathSegments.last)
        .toList();
    expect(names.where((String n) => n.endsWith('.tmp')), isEmpty);
    final ConversationStore again = ConversationStore(dir);
    await again.load();
    expect(again.all.first.messages.single.text, '在吗');
  });

  test('连着存两次不会把文件写成半截', () async {
    final ConversationStore store = ConversationStore(dir);
    await store.load();
    final Conversation c = await store.create(title: 'a');
    for (int i = 0; i < 40; i += 1) {
      c.messages.add(LlmMessage.user('第 $i 句'));
    }
    // 不等前一笔写完就再存一次：以前两笔叠在一起会把同一个文件写花。
    final Future<void> first = store.save(c);
    c.messages.add(const LlmMessage.user('最后一句'));
    final Future<void> second = store.save(c);
    await Future.wait(<Future<void>>[first, second]);

    final ConversationStore again = ConversationStore(dir);
    await again.load();
    final List<LlmMessage> back = again.all.first.messages;
    expect(back.length, 41);
    expect(back.last.text, '最后一句');
  });
}
