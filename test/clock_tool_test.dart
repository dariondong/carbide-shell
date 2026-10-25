import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/core/tools.dart';
import 'package:carbide_shell/tools/clock_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clock 说得出日期、时刻和时区', () async {
    final ClockTool tool = ClockTool();
    final ToolOutcome out = await tool.run(<String, Object?>{}, const ToolContext(workspace: '/tmp', desktop: true));

    expect(out.ok, isTrue);
    final DateTime now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    expect(out.stdout.contains('${now.year}-${two(now.month)}-${two(now.day)}'), isTrue);
    // 分钟可能刚好跳过，看小时就够
    expect(out.stdout.contains('${two(now.hour)}:'), isTrue);
    expect(out.stdout.contains('星期'), isTrue);
    expect(out.stdout.contains('UTC'), isTrue);
    expect(tool.classify(<String, Object?>{}), ToolRisk.read);
  });

  test('clock 不用参数，也不会被当成写操作', () {
    final ClockTool tool = ClockTool();
    expect(tool.name, 'clock');
    expect(tool.schema['properties'], isA<Map<String, Object?>>());
    expect((tool.schema['properties'] as Map<String, Object?>).isEmpty, isTrue);
    expect(tool.summarize(<String, Object?>{}).isNotEmpty, isTrue);
  });
}
