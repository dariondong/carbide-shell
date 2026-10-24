import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../core/models.dart';
import '../core/tools.dart';
import '../data/hosts.dart';
import '../data/secrets.dart';

/// One long-lived connection per host, reconnected on demand.
class SshPool {
  SshPool({required this.hosts, required this.secrets});

  final HostStore hosts;
  final SecretStore secrets;
  final Map<String, SSHClient> _clients = <String, SSHClient>{};

  /// Set when a known host suddenly presents another key.
  String lastKeyError = '';

  Future<SSHClient> connect(HostEntry entry) async {
    final SSHClient? open = _clients[entry.id];
    if (open != null && !open.isClosed) return open;

    lastKeyError = '';
    final String secret = await secrets.read(hostSecretKey(entry.id));
    final List<SSHIdentity> identities = <SSHIdentity>[];
    String? password;

    if (entry.auth == 'key' && secret.isNotEmpty) {
      try {
        identities.addAll(SSHKeyPair.fromPem(secret));
      } catch (e) {
        throw StateError('私钥读不出来：$e');
      }
    } else if (secret.isNotEmpty) {
      password = secret;
    }

    final SSHSocket socket = await SSHSocket.connect(
      entry.host,
      entry.port,
      timeout: const Duration(seconds: 15),
    );
    final SSHClient client = SSHClient(
      socket,
      username: entry.user,
      identities: identities.isEmpty ? null : identities,
      onPasswordRequest: password == null ? null : () => password,
      onVerifyHostKey: (String type, Uint8List fingerprint) {
        final String text = utf8.decode(fingerprint);
        if (entry.fingerprint.isEmpty) {
          unawaited(hosts.setFingerprint(entry.id, text));
          return true;
        }
        if (entry.fingerprint == text) return true;
        lastKeyError = '主机密钥变了。记录的是 ${entry.fingerprint}，这次是 $text。';
        return false;
      },
      keepAliveInterval: const Duration(seconds: 15),
      handshakeTimeout: const Duration(seconds: 20),
    );
    await client.authenticated;
    _clients[entry.id] = client;
    return client;
  }

  Future<void> drop(String hostId) async {
    final SSHClient? client = _clients.remove(hostId);
    client?.close();
  }

  Future<void> dropAll() async {
    for (final String id in _clients.keys.toList()) {
      await drop(id);
    }
  }
}

HostEntry? _resolveHost(HostStore hosts, String name) {
  final String wanted = name.trim();
  if (wanted.isNotEmpty) return hosts.byName(wanted);
  if (hosts.hosts.length == 1) return hosts.hosts.first;
  return null;
}

const Set<String> _readVerbs = <String>{
  'ls', 'll', 'cat', 'head', 'tail', 'less', 'wc', 'grep', 'egrep', 'find',
  'df', 'du', 'free', 'uptime', 'whoami', 'id', 'uname', 'hostname', 'date',
  'ps', 'pwd', 'echo', 'stat', 'nproc', 'lscpu', 'lsblk', 'ip', 'ss',
  'netstat', 'ping', 'dig', 'nslookup', 'journalctl', 'dmesg', 'systemctl',
  'docker', 'podman', 'git', 'tmux', 'crontab', 'getent',
};

/// True only when every command in the line starts with a verb we know reads.
bool isReadOnlyCommand(String command) {
  final List<String> parts = command.split(RegExp(r'(\|\||&&|[;|])'));
  bool sawOne = false;
  for (final String part in parts) {
    final String text = part.trim();
    if (text.isEmpty) continue;
    sawOne = true;
    final String word = text.split(RegExp(r'\s+')).first.split('/').last;
    if (!_readVerbs.contains(word)) return false;
    if (text.contains('>') || text.contains('>>')) return false;
  }
  return sawOne;
}

class SshExecTool extends Tool {
  SshExecTool(this.pool, this.hosts);

  final SshPool pool;
  final HostStore hosts;

  @override
  String get name => 'ssh_exec';

  @override
  String get description =>
      '在一台已保存的主机上运行一条命令，返回 stdout、stderr 和退出码。需要交互的命令不要用这个。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'host': <String, Object?>{'type': 'string', 'description': '主机名，来自主机列表'},
          'command': <String, Object?>{'type': 'string', 'description': '要执行的命令'},
        },
        'required': <String>['command'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) =>
      isReadOnlyCommand(readString(args, 'command')) ? ToolRisk.read : ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String host = readString(args, 'host', fallback: 'default');
    return '$host\$ ${readString(args, 'command')}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String command = readString(args, 'command').trim();
    if (command.isEmpty) return const ToolOutcome.failure('命令是空的。');
    final HostEntry? entry = _resolveHost(hosts, readString(args, 'host'));
    if (entry == null) {
      return ToolOutcome.failure(
        readString(args, 'host').isEmpty ? '没有指定主机，而且主机列表里不止一台。' : '主机列表里没有这台。',
      );
    }
    try {
      final SSHClient client = await pool.connect(entry);
      final SSHRunResult result =
          await client.runWithResult(command).timeout(context.timeout);
      return ToolOutcome.success(
        stdout: utf8.decode(result.stdout, allowMalformed: true),
        stderr: utf8.decode(result.stderr, allowMalformed: true),
        exitCode: result.exitCode,
        meta: <String, Object?>{'host': entry.name},
      );
    } on TimeoutException {
      await pool.drop(entry.id);
      return ToolOutcome.failure('命令在等输入，${context.timeout.inSeconds} 秒后关掉了连接。');
    } catch (e) {
      await pool.drop(entry.id);
      final String hint = pool.lastKeyError.isEmpty ? '' : '${pool.lastKeyError} ';
      return ToolOutcome.failure('$hint连不上 ${entry.address}：$e');
    }
  }
}

class SshSftpTool extends Tool {
  SshSftpTool(this.pool, this.hosts);

  final SshPool pool;
  final HostStore hosts;

  @override
  String get name => 'ssh_sftp';

  @override
  String get description => '在主机上列目录、读文件或写文件。写文件会覆盖原内容。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'host': <String, Object?>{'type': 'string'},
          'op': <String, Object?>{
            'type': 'string',
            'enum': <String>['list', 'read', 'write'],
          },
          'path': <String, Object?>{'type': 'string', 'description': '远端绝对路径'},
          'data': <String, Object?>{'type': 'string', 'description': 'op=write 时的内容'},
          'max_bytes': <String, Object?>{'type': 'integer', 'description': 'op=read 的上限，默认 65536'},
        },
        'required': <String>['op', 'path'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) =>
      readString(args, 'op') == 'write' ? ToolRisk.write : ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) {
    final String op = readString(args, 'op');
    final String path = readString(args, 'path');
    if (op == 'write') {
      return '写 ${readString(args, 'host', fallback: 'default')}:$path（${readString(args, 'data').length} 字符）';
    }
    return '$op ${readString(args, 'host', fallback: 'default')}:$path';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final HostEntry? entry = _resolveHost(hosts, readString(args, 'host'));
    if (entry == null) return const ToolOutcome.failure('没有指定主机。');
    final String op = readString(args, 'op');
    final String path = readString(args, 'path');
    if (path.isEmpty) return const ToolOutcome.failure('路径是空的。');
    try {
      final SSHClient client = await pool.connect(entry);
      final SftpClient sftp = await client.sftp();
      if (op == 'list') {
        final List<SftpName> names = await sftp.listdir(path).timeout(context.timeout);
        final StringBuffer b = StringBuffer();
        for (final SftpName n in names) {
          b.writeln('${n.filename}\t${n.attr.size ?? 0}\t${n.attr.modifyTime ?? 0}');
        }
        return ToolOutcome.success(stdout: b.toString());
      }
      if (op == 'read') {
        final int max = readInt(args, 'max_bytes', fallback: 65536);
        final SftpFile file = await sftp.open(path);
        final BytesBuilder builder = BytesBuilder();
        await for (final Uint8List chunk in file.read(length: max)) {
          builder.add(chunk);
        }
        await file.close();
        final Uint8List bytes = builder.takeBytes();
        return ToolOutcome.success(
          stdout: utf8.decode(bytes, allowMalformed: true),
          meta: <String, Object?>{'bytes': bytes.length},
        );
      }
      if (op == 'write') {
        final String data = readString(args, 'data');
        final SftpFile file = await sftp.open(
          path,
          mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate,
        );
        await file.writeBytes(Uint8List.fromList(utf8.encode(data)));
        await file.close();
        return ToolOutcome.success(
          stdout: '写了 ${data.length} 字符到 $path',
        );
      }
      return ToolOutcome.failure('不认识的 op：$op');
    } on TimeoutException {
      await pool.drop(entry.id);
      return const ToolOutcome.failure('SFTP 超时，连接已断开。');
    } catch (e) {
      return ToolOutcome.failure('SFTP 失败：$e');
    }
  }
}
