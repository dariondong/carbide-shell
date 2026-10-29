import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/data/settings.dart';
import 'package:carbide_shell/tools/http_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('carbide_http_approval');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('网络请求', () {
    late SettingsStore settings;

    setUp(() async {
      settings = SettingsStore(File('${dir.path}/settings.json'));
      await settings.load();
    });

    test('没加过的域名要问一句，批准了这一次才发', () async {
      final HttpTool tool = HttpTool(settings);
      // .invalid 是一定解析不到的名字：这一格只验门槛，不真去连。
      const Map<String, Object?> args = <String, Object?>{'url': 'https://no-such-host.invalid/x'};
      // 允许列表空着：GET 也当成写操作，审批卡上先让人看一眼。
      expect(tool.classify(args), ToolRisk.write);
      expect(tool.summarize(args).contains('不在允许列表'), isTrue);

      final ToolOutcome blocked = await tool.run(args, _ctx);
      expect(blocked.ok, isFalse);
      expect(blocked.error.contains('不在允许列表'), isTrue);

      // 批准过的那一次：不会真去连（域名不存在），但已经过了这道门。
      final ToolOutcome granted = await tool.run(args, _ctx.copyWith(granted: true));
      expect(granted.ok, isFalse);
      expect(granted.error.contains('不在允许列表'), isFalse);
    });

    test('加过的域名只读请求直接发', () async {
      settings.value.allowedDomains = <String>['example.com'];
      final HttpTool tool = HttpTool(settings);
      expect(
        tool.classify(<String, Object?>{'url': 'https://api.example.com/x'}),
        ToolRisk.read,
      );
      expect(
        tool.classify(<String, Object?>{'url': 'https://api.example.com/x', 'method': 'POST'}),
        ToolRisk.write,
      );
    });
  });
}
