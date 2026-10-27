import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../core/diff.dart';
import '../core/models.dart';
import '../core/patch.dart';
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
          'timeout_seconds': <String, Object?>{
            'type': 'integer',
            'description': '最长等多少秒，默认 15，最多 600。装东西、编译这种慢的往上加',
          },
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
    final int limit = readInt(args, 'timeout_seconds', fallback: context.timeout.inSeconds);
    final Duration wait = Duration(seconds: limit < 1 ? 1 : (limit > 600 ? 600 : limit));
    try {
      final SSHClient client = await pool.connect(entry);
      final SSHRunResult result = await client.runWithResult(command).timeout(wait);
      return ToolOutcome.success(
        stdout: utf8.decode(result.stdout, allowMalformed: true),
        stderr: utf8.decode(result.stderr, allowMalformed: true),
        exitCode: result.exitCode,
        meta: <String, Object?>{'host': entry.name},
      );
    } on TimeoutException {
      await pool.drop(entry.id);
      return ToolOutcome.failure(
          '命令在等输入，${wait.inSeconds} 秒后关掉了连接。要更久就把 timeout_seconds 写大一点。');
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
  String get description =>
      '在主机上列目录、读文件、写文件，或者换掉文件里的一小段。'
      'op=patch 只认唯一匹配，匹配到零处或多处就不写；preview=true 只回 diff 不落盘。'
      'op=write 会覆盖整份内容。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'host': <String, Object?>{'type': 'string'},
          'op': <String, Object?>{
            'type': 'string',
            'enum': <String>['list', 'read', 'write', 'patch'],
          },
          'path': <String, Object?>{'type': 'string', 'description': '远端绝对路径'},
          'data': <String, Object?>{'type': 'string', 'description': 'op=write 时的内容'},
          'max_bytes': <String, Object?>{'type': 'integer', 'description': 'op=read 的上限，默认 65536'},
          'old_string': <String, Object?>{
            'type': 'string',
            'description': 'op=patch 要换掉的那段，必须只出现一次',
          },
          'new_string': <String, Object?>{'type': 'string', 'description': 'op=patch 换成什么'},
          'preview': <String, Object?>{
            'type': 'boolean',
            'description': 'op=patch 只回 diff 不写盘，默认 false',
          },
        },
        'required': <String>['op', 'path'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) {
    final String op = readString(args, 'op');
    if (op == 'write') return ToolRisk.write;
    // 预览不落盘，看一眼不算改。
    if (op == 'patch') return args['preview'] == true ? ToolRisk.read : ToolRisk.write;
    return ToolRisk.read;
  }

  @override
  String summarize(Map<String, Object?> args) {
    final String op = readString(args, 'op');
    final String path = readString(args, 'path');
    if (op == 'write') {
      return '写 ${readString(args, 'host', fallback: 'default')}:$path（${readString(args, 'data').length} 字符）';
    }
    if (op == 'patch') {
      final bool preview = args['preview'] == true;
      final String old = readString(args, 'old_string');
      return '${preview ? '预览改' : '改'} ${readString(args, 'host', fallback: 'default')}:$path'
          '（换掉「${old.length > 24 ? '${old.substring(0, 24)}…' : old}」）';
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
      if (op == 'patch') {
        final String oldText = readString(args, 'old_string');
        final String newText = readString(args, 'new_string');
        final bool preview = args['preview'] == true;
        final SftpFile file = await sftp.open(path);
        final BytesBuilder builder = BytesBuilder();
        await for (final Uint8List chunk in file.read()) {
          builder.add(chunk);
          if (builder.length > 2 * 1024 * 1024) {
            await file.close();
            return const ToolOutcome.failure('文件超过 2 MB，不合适一处一处换，用 read 分段看。');
          }
        }
        await file.close();
        final String source = utf8.decode(builder.takeBytes(), allowMalformed: true);
        final PatchPlan plan = planPatch(source, oldText, newText);
        if (!plan.ok) return ToolOutcome.failure(plan.error);
        final DiffResult diff = unifiedDiff(
          source,
          plan.text,
          context: 3,
          aLabel: '${entry.name}:$path',
          bLabel: '${entry.name}:$path（改完）',
        );
        final int atLine = lineOf(source, plan.at);
        if (preview) {
          return ToolOutcome.success(
            stdout: '预览（没写盘）：改在第 $atLine 行，+${diff.added} −${diff.removed} 行\n'
                '${diff.text.trimRight()}\n'
                '确认无误就再来一次，preview 写 false。',
            meta: <String, Object?>{
              'preview': true,
              'line': atLine,
              'added': diff.added,
              'removed': diff.removed,
            },
          );
        }
        final SftpFile out = await sftp.open(
          path,
          mode: SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.truncate,
        );
        await out.writeBytes(Uint8List.fromList(utf8.encode(plan.text)));
        await out.close();
        return ToolOutcome.success(
          stdout: '改好了：$path 第 $atLine 行，+${diff.added} −${diff.removed} 行。\n'
              '${diff.text.trimRight()}',
          meta: <String, Object?>{
            'preview': false,
            'line': atLine,
            'added': diff.added,
            'removed': diff.removed,
          },
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
