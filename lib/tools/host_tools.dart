import 'package:dartssh2/dartssh2.dart';

import '../core/models.dart';
import '../core/tools.dart';
import '../data/hosts.dart';
import '../data/secrets.dart';
import 'ssh_tools.dart';

/// 把一台新主机加进主机列表。
///
/// 只有 Advance Master 的对话才拿得到这个工具。给了连接池就先连一次：
/// 连不上就把刚写的密钥和那条主机一起撤掉，列表里不留连不通的东西。
class AddHostTool extends Tool {
  AddHostTool({required this.hosts, required this.secrets, this.pool});

  final HostStore hosts;
  final SecretStore secrets;

  /// 传了就先连一次验一下；测试里可以不传。
  final SshPool? pool;

  @override
  String get name => 'host_add';

  @override
  String get description =>
      '把一台新主机写进主机列表：名字、地址、端口、账号，加上密码或私钥。写进去之前会先连一次，连不上就不留下。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string', 'description': '列表里显示的名字，比如 web-01'},
          'host': <String, Object?>{'type': 'string', 'description': '地址或域名'},
          'port': <String, Object?>{'type': 'integer', 'description': '默认 22'},
          'user': <String, Object?>{'type': 'string', 'description': '登录账号，默认 root'},
          'auth': <String, Object?>{
            'type': 'string',
            'enum': <String>['password', 'key'],
            'description': 'password 用密码，key 用私钥',
          },
          'secret': <String, Object?>{'type': 'string', 'description': '密码，或者整份私钥 PEM'},
          'sudo_password': <String, Object?>{
            'type': 'string',
            'description': '只需要 sudo 时才填。会单独存着，以后 ssh_exec 的 sudo=true 直接用它',
          },
        },
        'required': <String>['name', 'host', 'secret'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String name = readString(args, 'name');
    final String host = readString(args, 'host');
    final int port = readInt(args, 'port', fallback: 22);
    final String user = readString(args, 'user', fallback: 'root');
    final bool key = readString(args, 'auth', fallback: 'password') == 'key';
    final bool sudo = readString(args, 'sudo_password').trim().isNotEmpty;
    return '加主机 $name = $user@$host:$port（${key ? '私钥' : '密码'}${sudo ? '，带 sudo' : ''}）';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String name = readString(args, 'name').trim();
    final String host = readString(args, 'host').trim();
    final String user = readString(args, 'user', fallback: 'root').trim();
    final String secret = readString(args, 'secret').trim();
    final String sudoPassword = readString(args, 'sudo_password').trim();
    final bool byKey = readString(args, 'auth', fallback: 'password') == 'key';
    final int port = readInt(args, 'port', fallback: 22);

    if (name.isEmpty || host.isEmpty) {
      return const ToolOutcome.failure('名字和地址都得给。');
    }
    if (port < 1 || port > 65535) {
      return ToolOutcome.failure('端口不对：$port');
    }
    if (secret.isEmpty) {
      return const ToolOutcome.failure('密码或私钥要一起给，不然加进去也连不上。');
    }
    final HostEntry? same = hosts.byName(name);
    if (same != null) {
      return ToolOutcome.failure(
        '已经有一台叫 $name 的主机了（${same.address}）。换个名字，或者让用户自己去改那一台。',
      );
    }

    final HostEntry entry = HostEntry(
      id: HostStore.newId(),
      name: name,
      host: host,
      port: port,
      user: user.isEmpty ? 'root' : user,
      auth: byKey ? 'key' : 'password',
    );
    await secrets.write(hostSecretKey(entry.id), secret);
    if (sudoPassword.isNotEmpty) {
      await secrets.write(hostSudoKey(entry.id), sudoPassword);
    }
    await hosts.upsert(entry);

    final SshPool? probe = pool;
    if (probe != null) {
      try {
        final client = await probe.connect(entry);
        final SSHRunResult result = await client
            .runWithResult('echo carbide-ok')
            .timeout(const Duration(seconds: 12));
        if (result.exitCode != 0) throw StateError('连通了，但命令没跑通');
      } catch (e) {
        await hosts.remove(entry.id);
        await secrets.delete(hostSecretKey(entry.id));
        await secrets.delete(hostSudoKey(entry.id));
        return ToolOutcome.failure('连不上 ${entry.address}：$e');
      }
    }

    return ToolOutcome.success(
      stdout: '加好了：$name = ${entry.address}\n'
          '接下来 ssh_exec 和 ssh_sftp 的 host 写「$name」。',
    );
  }
}

/// 把一台主机从列表里删掉，它的密码或私钥一起删。
///
/// 跟 host_add 一对，只有 Advance Master 拿得到。
class RemoveHostTool extends Tool {
  RemoveHostTool({required this.hosts, required this.secrets});

  final HostStore hosts;
  final SecretStore secrets;

  @override
  String get name => 'host_remove';

  @override
  String get description => '把一台主机从列表里删掉，它的密码或私钥也跟着删。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string', 'description': '主机名，host_list 里看到的那个'},
        },
        'required': <String>['name'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) => '删主机 ${readString(args, 'name')}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final HostEntry? entry = hosts.byName(readString(args, 'name'));
    if (entry == null) {
      final String names = hosts.hosts.map((HostEntry h) => h.name).join('、');
      return ToolOutcome.failure(
          names.isEmpty ? '主机列表是空的。' : '没有叫这台的主机。现在有：$names');
    }
    await hosts.remove(entry.id);
    await secrets.delete(hostSecretKey(entry.id));
    await secrets.delete(hostSudoKey(entry.id));
    return ToolOutcome.success(stdout: '删掉了 ${entry.name}（${entry.address}），密钥也一起删了。');
  }
}
