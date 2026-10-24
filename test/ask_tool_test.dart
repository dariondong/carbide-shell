import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/tools/ask_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ToolContext context = ToolContext(workspace: '/tmp', desktop: false);

  test('有人答就带着回答回去', () async {
    final AskTool tool = AskTool(
      resolver: (AskRequest r) async {
        expect(r.question, '日志放哪？');
        expect(r.options, <String>['/var/log', '家目录']);
        return '/var/log';
      },
    );
    final ToolOutcome out = await tool.run(<String, Object?>{
      'question': '日志放哪？',
      'options': <String>['/var/log', '家目录'],
    }, context);
    expect(out.ok, isTrue);
    expect(out.stdout, '用户回答：/var/log');
  });

  test('没人看着就如实说，让模型自己拿主意', () async {
    final AskTool tool = AskTool();
    final ToolOutcome out = await tool.run(<String, Object?>{'question': '删哪个？'}, context);
    expect(out.ok, isTrue);
    expect(out.stdout.contains('没有人回答'), isTrue);
  });

  test('空问题不问', () async {
    final AskTool tool = AskTool(resolver: (AskRequest r) async => '不该走到这里');
    final ToolOutcome out = await tool.run(<String, Object?>{'question': '   '}, context);
    expect(out.ok, isFalse);
  });

  test('空白回答算没答', () async {
    final AskTool tool = AskTool(resolver: (AskRequest r) async => '  ');
    final ToolOutcome out = await tool.run(<String, Object?>{'question': '几点？'}, context);
    expect(out.ok, isFalse);
    expect(out.error.contains('没有回答'), isTrue);
  });

  test('选项最多四个，空的丢掉', () async {
    late List<String> seen;
    final AskTool tool = AskTool(
      resolver: (AskRequest r) async {
        seen = r.options;
        return '第一个';
      },
    );
    await tool.run(<String, Object?>{
      'question': '挑一个',
      'options': <Object>['a', '', 'b', 'c', 'd', 'e'],
    }, context);
    expect(seen, <String>['a', 'b', 'c', 'd']);
  });

  test('提问不算写操作，审批卡上就一行问题', () {
    final AskTool tool = AskTool();
    expect(tool.classify(<String, Object?>{}), ToolRisk.read);
    expect(tool.summarize(<String, Object?>{'question': '删哪个？'}), '问：删哪个？');
  });
}
