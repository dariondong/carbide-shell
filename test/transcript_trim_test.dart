import 'dart:io';

import 'package:carbide_shell/core/agent.dart';
import 'package:carbide_shell/core/conversation.dart';
import 'package:carbide_shell/core/journal.dart';
import 'package:carbide_shell/core/llm_base.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/policy.dart';
import 'package:carbide_shell/core/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// 记下每次请求看到的上下文。
class RecorderProvider implements LlmProvider {
  final List<List<LlmMessage>> seen = <List<LlmMessage>>[];

  @override
  String get label => 'recorder';

  @override
  Future<LlmReply> chat({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
    CancelToken? cancel,
    void Function(String delta)? onText,
  }) async {
    seen.add(messages.toList(growable: false));
    return const LlmReply(text: '好。');
  }
}

AgentLoop buildLoop(
  LlmProvider provider, {
  List<LlmMessage>? messages,
  int maxContextChars = 60000,
}) {
  return AgentLoop(
    llm: provider,
    registry: ToolRegistry(),
    policy: ApprovalPolicy(mode: ApprovalMode.autoRead),
    journal: MemoryJournal(),
    context: const ToolContext(workspace: '/tmp/carbide', desktop: true),
    maxContextChars: maxContextChars,
    messages: messages,
  );
}

void main() {
  test('记录不长的时候一条不动', () {
    final List<LlmMessage> messages = <LlmMessage>[
      const LlmMessage.user('看看磁盘'),
      const LlmMessage.assistant('97%。'),
    ];
    expect(trimTranscript(messages), 0);
    expect(messages.length, 2);
  });

  test('太长就从最早的收，收起的那几条不再占内存', () {
    final List<LlmMessage> messages = <LlmMessage>[];
    for (int i = 0; i < 40; i += 1) {
      messages.add(LlmMessage.user('第 $i 句 ${'x' * 500}'));
      messages.add(const LlmMessage.assistant('收到。'));
    }
    final int dropped = trimTranscript(messages, maxChars: 4000, keep: 6);
    expect(dropped, greaterThan(0));
    expect(messages.length, lessThan(80));
    expect(messages.length, greaterThanOrEqualTo(6));
    expect(messageWeightTotal(messages), lessThanOrEqualTo(4000 + 1000));
  });

  test('收起之后头一条不能是工具结果', () {
    final List<LlmMessage> messages = <LlmMessage>[];
    for (int i = 0; i < 30; i += 1) {
      messages.add(LlmMessage.user('跑第 $i 条 ${'y' * 300}'));
      messages.add(LlmMessage.assistant('开始。', calls: <LlmToolCall>[
        LlmToolCall(id: 'c$i', name: 'spy', args: <String, Object?>{'command': 'df -h'}),
      ]));
      messages.add(LlmMessage.toolResult(
          text: 'ok ${'z' * 300}', toolCallId: 'c$i', toolName: 'spy'));
    }
    final int dropped = trimTranscript(messages, maxChars: 3000, keep: 4);
    expect(dropped, greaterThan(0));
    expect(messages.first.role, isNot(LlmRole.tool));
  });

  test('存一次就把超出的部分收掉，条数记下来，下次读还在', () async {
    final Directory dir = await Directory.systemTemp.createTemp('carbide_trim');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final ConversationStore store = ConversationStore(dir);
    await store.load();
    final Conversation c = await store.create(title: '长对话');
    for (int i = 0; i < 40; i += 1) {
      c.messages.add(LlmMessage.user('第 $i 句 ${'x' * 2000}'));
    }
    await store.save(c);
    expect(c.dropped, greaterThan(0));
    expect(c.messages.length, greaterThanOrEqualTo(kTranscriptKeep));
    expect(c.messages.length, lessThan(40));

    final ConversationStore again = ConversationStore(dir);
    await again.load();
    expect(again.all.first.dropped, c.dropped);
    expect(again.all.first.messages.length, c.messages.length);
  });

  test('更早的图片不带进请求，最近那一组留着', () async {
    final RecorderProvider provider = RecorderProvider();
    final AgentLoop loop = buildLoop(
      provider,
      messages: <LlmMessage>[
        LlmMessage.user('', images: <String>['data:image/png;base64,AAAA']),
        const LlmMessage.assistant('这张是机柜背面。'),
      ],
    );
    await loop.send('再看这张', images: <String>['data:image/png;base64,BBBB']);

    final List<LlmMessage> sent = provider.seen.first;
    final LlmMessage old = sent.firstWhere((LlmMessage m) => m.text.contains('图片已收起'));
    expect(old.images, isEmpty);
    expect(sent.last.images, <String>['data:image/png;base64,BBBB']);
    // 记录本身不动：换掉的只是发出去的那一份。
    expect(loop.history.first.images.length, 1);
  });

  test('记录被收短之后起点跟着回到范围内', () async {
    final RecorderProvider provider = RecorderProvider();
    final List<LlmMessage> messages = <LlmMessage>[];
    for (int i = 0; i < 30; i += 1) {
      messages.add(LlmMessage.user('第 $i 句 ${'x' * 200}'));
      messages.add(const LlmMessage.assistant('嗯。'));
    }
    final AgentLoop loop = buildLoop(provider, messages: messages, maxContextChars: 800);
    await loop.send('接着来');
    // 模拟保存时把前面收掉，起点就落在范围外了。
    loop.history.removeRange(0, 40);
    await loop.send('还在吗');
    expect(provider.seen.length, 2);
    expect(provider.seen.last.last.text, contains('还在吗'));
  });
}

int messageWeightTotal(List<LlmMessage> messages) {
  int total = 0;
  for (final LlmMessage m in messages) {
    total += messageWeight(m);
  }
  return total;
}
