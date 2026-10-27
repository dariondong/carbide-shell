import 'dart:io';

import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/data/hosts.dart';
import 'package:carbide_shell/data/secrets.dart';
import 'package:carbide_shell/tools/ssh_tools.dart';
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

  group('ssh_exec sudo', () {
    test('sudo 的命令是写操作，审批卡上带 sudo', () {
      final SshExecTool tool = SshExecTool(pool, hosts);
      final Map<String, Object?> args = <String, Object?>{
        'host': 'mgr',
        'command': 'ufw status verbose',
        'sudo': true,
      };
      expect(tool.summarize(args), contains('sudo ufw status verbose'));
      expect(tool.classify(args), ToolRisk.write);
    });

    test('没存 sudo 密码就直说，不让把密码写进命令', () async {
      await hosts.upsert(HostEntry(id: 'h1', name: 'mgr', host: '127.0.0.1', port: 1, user: 'root'));
      final ToolOutcome out = await SshExecTool(pool, hosts).run(<String, Object?>{
        'host': 'mgr',
        'command': 'id',
        'sudo': true,
      }, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('sudo 密码'));
    });
  });
}
