import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/data/settings.dart';
import 'package:carbide_shell/tools/http_tool.dart';
import 'package:carbide_shell/tools/net_tool.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  late Directory dir;
  late SettingsStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cbs-net');
    store = SettingsStore(File('${dir.path}/settings.json'));
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('域名取法', () {
    test('网址只留主机名，前缀的 * 和点去掉', () {
      expect(HttpAllowTool.hostOf('https://API.Example.com/a/b?c=1'), 'api.example.com');
      expect(HttpAllowTool.hostOf('example.com:8443'), 'example.com');
      expect(HttpAllowTool.hostOf('*.foo.bar'), 'foo.bar');
      expect(HttpAllowTool.hostOf('localhost'), 'localhost');
    });

    test('不像域名的不收', () {
      expect(HttpAllowTool.hostOf('随便写的'), '');
      expect(HttpAllowTool.hostOf(''), '');
      expect(HttpAllowTool.hostOf('not a domain'), '');
    });
  });

  group('允许列表', () {
    test('空的时候如实说一个都不许', () async {
      final ToolOutcome out = await HttpAllowTool(store).run(<String, Object?>{}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('空的'));
    });

    test('加一条就落盘，子域也跟着放行', () async {
      final ToolOutcome out = await HttpAllowTool(store)
          .run(<String, Object?>{'domain': 'https://api.example.com/x'}, _ctx);
      expect(out.ok, isTrue);
      expect(store.value.allowedDomains, <String>['api.example.com']);

      final HttpTool http = HttpTool(store);
      expect(
        http.classify(<String, Object?>{
          'method': 'GET',
          'url': 'https://sub.api.example.com/x',
        }),
        ToolRisk.read,
        reason: '进了允许列表的域名，GET 不该再问一句',
      );

      // 换一个 store 重新读那个文件，列表还在。
      final SettingsStore again = SettingsStore(File('${dir.path}/settings.json'));
      await again.load();
      expect(again.value.allowedDomains, <String>['api.example.com']);
    });

    test('重复加不会变成两条', () async {
      final HttpAllowTool tool = HttpAllowTool(store);
      await tool.run(<String, Object?>{'domain': 'example.com'}, _ctx);
      final ToolOutcome out = await tool.run(
          <String, Object?>{'domain': 'https://www.example.com/', 'action': 'add'}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('已经在列表里'));
      expect(store.value.allowedDomains, <String>['example.com']);
    });

    test('删掉之后又回到要问一句', () async {
      final HttpAllowTool tool = HttpAllowTool(store);
      await tool.run(<String, Object?>{'domain': 'example.com'}, _ctx);
      final ToolOutcome out =
          await tool.run(<String, Object?>{'domain': 'www.example.com', 'action': 'remove'}, _ctx);
      expect(out.ok, isTrue);
      expect(store.value.allowedDomains, isEmpty);
      expect(
        HttpTool(store).classify(<String, Object?>{'url': 'https://www.example.com/x'}),
        ToolRisk.write,
      );
    });

    test('删一个本来就没有的说一句，不改文件', () async {
      final ToolOutcome out = await HttpAllowTool(store)
          .run(<String, Object?>{'domain': 'nope.example', 'action': 'remove'}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('本来就不在'));
      expect(store.value.allowedDomains, isEmpty);
    });

    test('看一眼算读，加和删算写', () {
      final HttpAllowTool tool = HttpAllowTool(store);
      expect(tool.classify(<String, Object?>{}), ToolRisk.read);
      expect(tool.classify(<String, Object?>{'action': 'list', 'domain': 'a.b'}), ToolRisk.read);
      expect(tool.classify(<String, Object?>{'domain': 'a.b'}), ToolRisk.write);
      expect(
          tool.classify(<String, Object?>{'domain': 'a.b', 'action': 'remove'}), ToolRisk.write);
    });

    test('不像域名的写进来就据实拒绝', () async {
      final ToolOutcome out = await HttpAllowTool(store)
          .run(<String, Object?>{'domain': '随便写的'}, _ctx);
      expect(out.ok, isFalse);
      expect(store.value.allowedDomains, isEmpty);
    });
  });
}
