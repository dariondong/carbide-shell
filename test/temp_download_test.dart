import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/data/hosts.dart';
import 'package:carbide_shell/data/secrets.dart';
import 'package:carbide_shell/data/temp_files.dart';
import 'package:carbide_shell/tools/ssh_tools.dart';
import 'package:carbide_shell/tools/temp_tools.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

void main() {
  late Directory dir;
  late HostStore hosts;
  late SshPool pool;

  setUp(() {
    dir = Directory(
        '${Directory.systemTemp.path}/carbide_ssh_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    hosts = HostStore(File('${dir.path}/hosts.json'));
    pool = SshPool(hosts: hosts, secrets: MemorySecretStore());
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  group('temp_download', () {
    late TempFiles files;
    late TempDownloadTool tool;

    setUp(() {
      files = TempFiles(Directory('${dir.path}/temp'));
      files.ensure();
      tool = TempDownloadTool(files: files, pool: pool, hosts: hosts);
    });

    test('没给远端路径就说', () async {
      final ToolOutcome out = await tool.run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('remote'));
    });

    test('没有主机就不去连', () async {
      final ToolOutcome out = await tool.run(
          <String, Object?>{'remote': '/var/log/auth.log'}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('主机'));
    });

    test('临时区外的路径不认', () async {
      await hosts.upsert(HostEntry(id: 'h1', name: 'mgr', host: '127.0.0.1', port: 1, user: 'root'));
      final ToolOutcome out = await tool.run(<String, Object?>{
        'remote': '/var/log/auth.log',
        'host': 'mgr',
        'path': '/etc/passwd',
      }, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('临时文件区'));
    });

    test('审批卡上念得出从哪拉什么', () {
      expect(
        tool.summarize(<String, Object?>{'host': 'mgr', 'remote': '/var/log/auth.log'}),
        contains('/var/log/auth.log'),
      );
    });
  });
}
