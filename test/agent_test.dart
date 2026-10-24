import 'package:flutter_test/flutter_test.dart';
import 'package:carbide_shell/core/agent.dart';
import 'package:carbide_shell/core/journal.dart';
import 'package:carbide_shell/core/llm_base.dart';
import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/policy.dart';
import 'package:carbide_shell/core/tools.dart';

class ScriptedProvider implements LlmProvider {
  ScriptedProvider(this.replies);

  final List<LlmReply> replies;
  int calls = 0;
  String lastSystem = '';

  @override
  String get label => 'scripted';

  @override
  Future<LlmReply> chat({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
    CancelToken? cancel,
  }) async {
    lastSystem = system;
    if (calls >= replies.length) return const LlmReply(text: '没有更多步骤。');
    return replies[calls++];
  }
}

class SpyTool extends Tool {
  SpyTool({this.risk = ToolRisk.read, this.output = 'ok'});

  final ToolRisk risk;
  final String output;
  int runs = 0;
  Map<String, Object?> lastArgs = <String, Object?>{};

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
  ToolRisk classify(Map<String, Object?> args) => risk;

  @override
  String summarize(Map<String, Object?> args) => readString(args, 'command');

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    runs += 1;
    lastArgs = args;
    return ToolOutcome.success(stdout: output);
  }
}

class FixedApprover implements Approver {
  FixedApprover(this.answer);

  final bool answer;
  List<ApprovalRequest> seen = <ApprovalRequest>[];

  @override
  Future<bool> confirm(ApprovalRequest request) async {
    seen.add(request);
    return answer;
  }
}

AgentLoop buildLoop(LlmProvider provider, ToolRegistry registry, {Approver? approver, ApprovalMode mode = ApprovalMode.autoRead, int maxSteps = 12}) {
  return AgentLoop(
    llm: provider,
    registry: registry,
    policy: ApprovalPolicy(mode: mode),
    journal: MemoryJournal(),
    context: const ToolContext(workspace: '/tmp/carbide', desktop: true),
    approver: approver,
    maxSteps: maxSteps,
  );
}

ToolRegistry registryWith(SpyTool tool) {
  final ToolRegistry r = ToolRegistry();
  r.register(tool);
  return r;
}

void main() {
  test('读工具直接跑，结果回给模型', () async {
    final SpyTool tool = SpyTool(output: 'disk 97%');
    final ScriptedProvider provider = ScriptedProvider(<LlmReply>[
      const LlmReply(
        text: '先看一眼。',
        calls: <LlmToolCall>[
          LlmToolCall(id: 'c1', name: 'spy', args: <String, Object?>{'command': 'df -h'}),
        ],
      ),
      const LlmReply(text: '根分区 97%。'),
    ]);
    final AgentLoop loop = buildLoop(provider, registryWith(tool));

    final String answer = await loop.send('看一下磁盘');

    expect(answer, '根分区 97%。');
    expect(tool.runs, 1);
    final List<LlmMessage> tools = loop.history.where((LlmMessage m) => m.isTool).toList();
    expect(tools.length, 1);
    expect(tools.first.text.contains('disk 97%'), isTrue);
    expect(loop.step, 2);
  });

  test('写工具在没界面确认的时候不执行', () async {
    final SpyTool tool = SpyTool(risk: ToolRisk.write);
    final ScriptedProvider provider = ScriptedProvider(<LlmReply>[
      const LlmReply(calls: <LlmToolCall>[
        LlmToolCall(id: 'c1', name: 'spy', args: <String, Object?>{'command': 'systemctl restart nginx'}),
      ]),
      const LlmReply(text: '没有执行。'),
    ]);
    final AgentLoop loop = buildLoop(provider, registryWith(tool));

    await loop.send('重启 nginx');

    expect(tool.runs, 0);
    final LlmMessage result = loop.history.firstWhere((LlmMessage m) => m.isTool);
    expect(result.text.contains('需要用户确认'), isTrue);
  });

  test('用户拒绝后不执行', () async {
    final SpyTool tool = SpyTool(risk: ToolRisk.write);
    final ScriptedProvider provider = ScriptedProvider(<LlmReply>[
      const LlmReply(calls: <LlmToolCall>[
        LlmToolCall(id: 'c1', name: 'spy', args: <String, Object?>{'command': 'systemctl restart nginx'}),
      ]),
      const LlmReply(text: '那就不动了。'),
    ]);
    final FixedApprover approver = FixedApprover(false);
    final AgentLoop loop = buildLoop(provider, registryWith(tool), approver: approver);

    await loop.send('重启 nginx');

    expect(approver.seen.length, 1);
    expect(tool.runs, 0);
  });

  test('用户批准后执行', () async {
    final SpyTool tool = SpyTool(risk: ToolRisk.write, output: 'restarted');
    final ScriptedProvider provider = ScriptedProvider(<LlmReply>[
      const LlmReply(calls: <LlmToolCall>[
        LlmToolCall(id: 'c1', name: 'spy', args: <String, Object?>{'command': 'systemctl restart nginx'}),
      ]),
      const LlmReply(text: '重启好了。'),
    ]);
    final AgentLoop loop = buildLoop(provider, registryWith(tool), approver: FixedApprover(true));

    await loop.send('重启 nginx');

    expect(tool.runs, 1);
  });

  test('危险命令即使批准也被拦', () async {
    final SpyTool tool = SpyTool(risk: ToolRisk.write);
    final ScriptedProvider provider = ScriptedProvider(<LlmReply>[
      const LlmReply(calls: <LlmToolCall>[
        LlmToolCall(id: 'c1', name: 'spy', args: <String, Object?>{'command': 'rm -rf /var/log'}),
      ]),
      const LlmReply(text: '这条被拦下了。'),
    ]);
    final FixedApprover approver = FixedApprover(true);
    final AgentLoop loop = buildLoop(provider, registryWith(tool), approver: approver);

    await loop.send('清日志');

    expect(approver.seen, isEmpty);
    expect(tool.runs, 0);
    final LlmMessage result = loop.history.firstWhere((LlmMessage m) => m.isTool);
    expect(result.text.contains('危险规则'), isTrue);
  });

  test('步数用尽就停', () async {
    final SpyTool tool = SpyTool();
    final List<LlmReply> replies = <LlmReply>[
      for (int i = 0; i < 6; i += 1)
        LlmReply(calls: <LlmToolCall>[
          LlmToolCall(id: 'c$i', name: 'spy', args: <String, Object?>{'command': 'ls'}),
        ]),
    ];
    final AgentLoop loop = buildLoop(ScriptedProvider(replies), registryWith(tool), maxSteps: 3);

    final String answer = await loop.send('一直看');

    expect(answer.contains('步数上限'), isTrue);
    expect(loop.step, 3);
  });

  test('不存在的工具不会让循环塌掉', () async {
    final ScriptedProvider provider = ScriptedProvider(<LlmReply>[
      const LlmReply(calls: <LlmToolCall>[
        LlmToolCall(id: 'c1', name: 'nope', args: <String, Object?>{}),
      ]),
      const LlmReply(text: '没有这个能力。'),
    ]);
    final AgentLoop loop = buildLoop(provider, ToolRegistry());

    final String answer = await loop.send('干点别的');

    expect(answer, '没有这个能力。');
    final LlmMessage result = loop.history.firstWhere((LlmMessage m) => m.isTool);
    expect(result.text.contains('没有这个工具'), isTrue);
  });

  test('模型报错变成一句话，不抛异常', () async {
    final AgentLoop loop = buildLoop(_ThrowingProvider(), ToolRegistry());
    final String answer = await loop.send('看看');
    expect(answer.contains('模型请求失败'), isTrue);
  });

  test('环境说明会拼进系统提示', () async {
    final SpyTool tool = SpyTool();
    final ScriptedProvider provider = ScriptedProvider(<LlmReply>[const LlmReply(text: '好')]);
    final AgentLoop loop = AgentLoop(
      llm: provider,
      registry: registryWith(tool),
      policy: ApprovalPolicy(),
      journal: MemoryJournal(),
      context: const ToolContext(workspace: '/tmp/carbide', desktop: false),
      environment: () => 'web-01 = root@10.0.0.21:22',
    );

    await loop.send('看看');

    expect(provider.lastSystem.contains('Carbide Shell'), isTrue);
    expect(provider.lastSystem.contains('web-01 = root@10.0.0.21:22'), isTrue);
  });

  test('截断保留头尾并标出省略', () {
    final String text = 'A' * 4000 + 'B' * 1000;
    final String cut = truncateOutput(text, head: 100, tail: 50);
    expect(cut.startsWith('A'), isTrue);
    expect(cut.endsWith('B'), isTrue);
    expect(cut.contains('省略'), isTrue);
    expect(truncateOutput('short'), 'short');
  });
}

class _ThrowingProvider implements LlmProvider {
  @override
  String get label => 'boom';

  @override
  Future<LlmReply> chat({
    required String system,
    required List<LlmMessage> messages,
    required List<ToolSpec> tools,
    CancelToken? cancel,
  }) async {
    throw LlmException('连不上');
  }
}
