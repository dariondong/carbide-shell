import 'package:flutter_test/flutter_test.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/openai.dart';

void main() {
  group('OpenAI 兼容接口', () {
    test('地址拼接', () {
      expect(OpenAiProvider(baseUrl: 'https://a.example.com', apiKey: '', model: 'm')
          .endpoint().toString(), 'https://a.example.com/v1/chat/completions');
      expect(OpenAiProvider(baseUrl: 'https://a.example.com/v1/', apiKey: '', model: 'm')
          .endpoint().toString(), 'https://a.example.com/v1/chat/completions');
      expect(
          OpenAiProvider(
                  baseUrl: 'https://a.example.com/v1/chat/completions',
                  apiKey: '',
                  model: 'm')
              .endpoint()
              .toString(),
          'https://a.example.com/v1/chat/completions');
    });

    test('请求体带工具和工具结果', () {
      final OpenAiProvider p = OpenAiProvider(baseUrl: 'https://x', apiKey: 'k', model: 'm');
      final Map<String, Object?> body = p.payload(
        system: 'sys',
        messages: <LlmMessage>[
          const LlmMessage.user('hi'),
          const LlmMessage.assistant('', calls: <LlmToolCall>[
            LlmToolCall(id: 'c1', name: 'ssh_exec', args: <String, Object?>{'command': 'ls'}),
          ]),
          const LlmMessage.toolResult(text: 'a b', toolCallId: 'c1', toolName: 'ssh_exec'),
        ],
        tools: const <ToolSpec>[
          ToolSpec(name: 'ssh_exec', description: 'run', schema: <String, Object?>{}),
        ],
      );
      final List<Object?> msg = body['messages']! as List<Object?>;
      expect(msg.length, 4);
      final Map<String, Object?> call = msg[2]! as Map<String, Object?>;
      expect(call['tool_calls'], isNotNull);
      final Map<String, Object?> toolMsg = msg[3]! as Map<String, Object?>;
      expect(toolMsg['role'], 'tool');
      expect(toolMsg['tool_call_id'], 'c1');
      expect((body['tools']! as List<Object?>).length, 1);
      p.close();
    });

    test('解析返回里的工具调用', () {
      final LlmReply reply = parseChatResponse(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'content': '看一下',
              'tool_calls': <Object?>[
                <String, Object?>{
                  'id': 'call_1',
                  'type': 'function',
                  'function': <String, Object?>{
                    'name': 'ssh_exec',
                    'arguments': '{"command":"df -h"}',
                  },
                },
              ],
            },
          },
        ],
        'usage': <String, Object?>{'prompt_tokens': 10, 'completion_tokens': 5},
      });
      expect(reply.text, '看一下');
      expect(reply.calls.length, 1);
      expect(reply.calls.first.name, 'ssh_exec');
      expect(reply.calls.first.args['command'], 'df -h');
      expect(reply.usage.total, 15);
    });

    test('读得出缓存命中', () {
      final LlmReply reply = parseChatResponse(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': '好'},
          },
        ],
        'usage': <String, Object?>{
          'prompt_tokens': 2000,
          'completion_tokens': 60,
          'prompt_tokens_details': <String, Object?>{'cached_tokens': 1600},
        },
      });
      expect(reply.usage.prompt, 2000);
      expect(reply.usage.cached, 1600);
      expect(reply.usage.cacheHitRate, closeTo(0.8, 0.001));
    });

    test('没有缓存字段时命中率是零', () {
      final LlmUsage u = usageFrom(<String, Object?>{'prompt_tokens': 100});
      expect(u.cacheHitRate, 0);
      expect(const LlmUsage().cacheHitRate, 0);
    });

    test('没有 choices 就报错', () {
      expect(() => parseChatResponse(<String, Object?>{}), throwsA(isA<Exception>()));
    });
  });
}
