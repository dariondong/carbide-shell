import 'package:carbide_shell/core/compact.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

LlmMessage _user(String text) => LlmMessage.user(text);

LlmMessage _answer(String text, {List<LlmToolCall> calls = const <LlmToolCall>[]}) =>
    LlmMessage.assistant(text, calls: calls);

LlmMessage _tool(String id, String text) =>
    LlmMessage.toolResult(text: text, toolCallId: id, toolName: 'ssh_exec');

/// 一问一答加一次工具往返算一圈，每圈四千字上下。
List<LlmMessage> _turns(int n) {
  final List<LlmMessage> out = <LlmMessage>[];
  for (int i = 0; i < n; i += 1) {
    out.add(_user('第 $i 圈：磁盘又满了 ${'x' * 2000}'));
    out.add(_answer('', calls: <LlmToolCall>[
      LlmToolCall(
        id: 'c$i',
        name: 'ssh_exec',
        args: <String, Object?>{'command': 'df -h /var'},
      ),
    ]));
    out.add(_tool('c$i', '/dev/vda1 100% ${'y' * 2000}'));
  }
  return out;
}

void main() {
  test('短记录不用压', () {
    final List<LlmMessage> short = <LlmMessage>[
      _user('看磁盘'),
      _answer('看完了'),
      _user('再清一下日志'),
      _answer('清了'),
      _user('谢谢'),
    ];
    expect(compactCut(short), 0);
  });

  test('长记录从一条用户消息开始留', () {
    final List<LlmMessage> talk = _turns(8);
    final int cut = compactCut(talk);
    expect(cut, greaterThan(0));
    expect(cut, lessThan(talk.length));
    // 尾巴不能从工具结果开始，也不能从模型的半句话开始。
    expect(talk[cut].role, LlmRole.user);
    // 前面确实有一大段可压的东西。
    expect(cut, greaterThanOrEqualTo(2));
  });

  test('尾巴留够几条，不会把一场对话全压掉', () {
    final List<LlmMessage> talk = _turns(8);
    final int cut = compactCut(talk);
    expect(talk.length - cut, greaterThanOrEqualTo(3));
  });

  test('要收的那一段铺成人话：用户、助手、调用、结果都在', () {
    final List<LlmMessage> talk = _turns(4);
    final String ask = compactPrompt(talk.sublist(0, 9));
    expect(ask, contains('用户：第 0 圈'));
    expect(ask, contains('调用 ssh_exec(command: df -h /var)'));
    expect(ask, contains('工具 ssh_exec 结果：'));
    expect(ask, contains('只写摘要本身'));
  });

  test('太长的一行会截断，不会把整份输出再发一遍', () {
    final LlmMessage huge = _tool('c9', 'z' * 5000);
    final String ask = compactPrompt(<LlmMessage>[huge]);
    expect(ask.length, lessThan(1000));
    expect(ask, contains('…'));
  });

  test('预算调小就留得更少', () {
    final List<LlmMessage> talk = _turns(8);
    final int wide = compactCut(talk, keepChars: 20000);
    final int tight = compactCut(talk, keepChars: 6000);
    // 预算大 = 尾巴长 = 起点靠前。
    expect(wide, lessThan(tight));
    expect(tight, greaterThan(0));
  });
}
