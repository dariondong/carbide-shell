import 'package:carbide_shell/core/conversation.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('每条消息的 token', () {
    test('回答带着 token 存下来读回来还在', () {
      final LlmMessage m = LlmMessage.assistant(
        '磁盘 92%',
        calls: <LlmToolCall>[
          const LlmToolCall(id: 'c1', name: 'clock', args: <String, Object?>{}),
        ],
        usage: const LlmUsage(prompt: 1200, completion: 80, cached: 900),
      );
      final Map<String, Object?> json = messageToJson(m);
      expect(json['usage'], isA<Map<String, Object?>>());
      final LlmMessage? back = messageFromJson(json);
      expect(back, isNotNull);
      expect(back!.usage.prompt, 1200);
      expect(back.usage.completion, 80);
      expect(back.usage.cached, 900);
      expect(back.usage.total, 1280);
      expect(back.usage.cacheHitRate, closeTo(0.75, 0.0001));
      expect(back.calls.length, 1);
    });

    test('没花 token 的就不写这一项', () {
      final Map<String, Object?> json = messageToJson(LlmMessage.user('在吗'));
      expect(json.containsKey('usage'), isFalse);
      final LlmMessage back = messageFromJson(json)!;
      expect(back.usage.total, 0);
    });

    test('旧记录里没有 usage 也读得出来', () {
      final LlmMessage? back = messageFromJson(<String, Object?>{
        'role': 'assistant',
        'text': '以前的回答',
      });
      expect(back, isNotNull);
      expect(back!.usage.total, 0);
    });

    test('只命中缓存没写进 json 时按 0 算', () {
      final LlmMessage back = messageFromJson(<String, Object?>{
        'role': 'assistant',
        'text': 'x',
        'usage': <String, Object?>{'prompt': 500, 'completion': 20},
      })!;
      expect(back.usage.cached, 0);
      expect(back.usage.cacheHitRate, 0);
    });
  });
}
