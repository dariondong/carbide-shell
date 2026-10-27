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
        '${Directory.systemTemp.path}/carbide_patch_${DateTime.now().microsecondsSinceEpoch}');
    dir.createSync(recursive: true);
    hosts = HostStore(File('${dir.path}/hosts.json'));
    pool = SshPool(hosts: hosts, secrets: MemorySecretStore());
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  group('ssh_sftp patch', () {
    test('预览不算改，落盘才算', () {
      final SshSftpTool tool = SshSftpTool(pool, hosts);
      expect(
        tool.classify(<String, Object?>{'op': 'patch', 'path': '/e', 'preview': true}),
        ToolRisk.read,
      );
      expect(tool.classify(<String, Object?>{'op': 'patch', 'path': '/e'}), ToolRisk.write);
      expect(tool.classify(<String, Object?>{'op': 'read', 'path': '/e'}), ToolRisk.read);
      expect(tool.classify(<String, Object?>{'op': 'write', 'path': '/e'}), ToolRisk.write);
    });

    test('审批卡上写清是预览还是真改', () {
      final SshSftpTool tool = SshSftpTool(pool, hosts);
      final String preview = tool.summarize(<String, Object?>{
        'op': 'patch',
        'path': '/etc/systemd/journald.conf',
        'old_string': '#SystemMaxUse=',
        'new_string': 'SystemMaxUse=500M',
        'preview': true,
      });
      expect(preview, contains('预览改'));
      expect(preview, contains('journald.conf'));
      expect(preview, contains('#SystemMaxUse='));
      final String real = tool.summarize(<String, Object?>{
        'op': 'patch',
        'path': '/etc/x',
        'old_string': 'a',
      });
      expect(real.startsWith('改 '), isTrue);
    });

    test('没有主机就不去连', () async {
      final ToolOutcome out = await SshSftpTool(pool, hosts).run(<String, Object?>{
        'op': 'patch',
        'path': '/etc/x',
        'old_string': 'a',
        'new_string': 'b',
      }, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('主机'));
    });
  });
}
