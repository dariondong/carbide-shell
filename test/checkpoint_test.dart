import 'package:carbide_shell/core/agent.dart';
import 'package:carbide_shell/core/journal.dart';
import 'package:carbide_shell/core/llm_base.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/policy.dart';
import 'package:carbide_shell/core/tools.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一句话回一个回答的假模型。
class _Scripted implements LlmProvider {
  _Scripted(this.replies);

  final List<LlmReply> replies;
  int calls = 0;

  @override
  String get label => 'scripted';

  @override
  Future<LlmReply> chat({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
    CancelToken? cancel,
    void Function(String delta)? onText,
  }) async {
    if (calls >= replies.length) return const LlmReply(text: '没有更多步骤。');
    return replies[calls++];
  }
}

class _EchoTool extends Tool {
  int runs = 0;

  @override
  String get name => 'spy';

  @override
  String get description => 'test tool';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'command': <String, Object?>{'type': 'string'},
        },
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => readString(args, 'command');

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    runs += 1;
    return const ToolOutcome.success(stdout: 'ok');
  }
}

void main() {
  test('跑着的时候每一步都存一次，中途退出不丢', () async {
    final _EchoTool tool = _EchoTool();
    final _Scripted provider = _Scripted(<LlmReply>[
      const LlmReply(
        text: '先看一眼。',
        calls: <LlmToolCall>[
          LlmToolCall(id: 'c1', name: 'spy', args: <String, Object?>{'command': 'df -h'}),
        ],
      ),
      const LlmReply(text: '根分区 97%。'),
    ]);
    final ToolRegistry registry = ToolRegistry()..register(tool);
    final AgentLoop loop = AgentLoop(
      llm: provider,
      registry: registry,
      policy: ApprovalPolicy(),
      journal: MemoryJournal(),
      context: const ToolContext(workspace: '/tmp/carbide', desktop: true),
    );
    int saves = 0;
    loop.onCheckpoint = () => saves += 1;

    await loop.send('看看磁盘');

    // 用户那句、模型要工具那一步、工具结果、最后回答：每一步都是一笔。
    expect(saves, greaterThanOrEqualTo(4));
    expect(tool.runs, 1);
  });
}
