import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../core/models.dart';
import '../core/tools.dart';
import '../data/hosts.dart';
import '../data/temp_files.dart';
import 'ssh_tools.dart';

/// 把临时文件区里的一个文件写到主机上。远端路径以 `/` 结尾时接上原文件名。
/// 写之前不建目录，parent 不存在就报错让调用方自己看。
Future<TempUpload> sftpUpload(
  SshPool pool,
  HostEntry entry,
  File local,
  String remote,
) async {
  final String name = local.path.split('/').last;
  String target = remote.trim();
  if (target.isEmpty) target = '/tmp/$name';
  if (target.endsWith('/')) target = '$target$name';
  final Uint8List bytes = await local.readAsBytes();
  final SSHClient client = await pool.connect(entry);
  final SftpClient sftp = await client.sftp();
  final SftpFile file = await sftp.open(
    target,
    mode: SftpFileOpenMode.write |
        SftpFileOpenMode.create |
        SftpFileOpenMode.truncate,
  );
  await file.writeBytes(bytes);
  await file.close();
  return TempUpload(path: target, bytes: bytes.length, host: entry.name);
}

class TempUpload {
  const TempUpload({required this.path, required this.bytes, required this.host});

  final String path;
  final int bytes;
  final String host;
}

HostEntry? hostForUpload(HostStore hosts, String name) {
  final String wanted = name.trim();
  if (wanted.isNotEmpty) return hosts.byName(wanted);
  if (hosts.hosts.length == 1) return hosts.hosts.first;
  return null;
}

/// 临时文件区：列、读、写、删。图片和压缩包只列得出来，内容读不了。
class TempFileTool extends Tool {
  TempFileTool(this.files);

  final TempFiles files;

  @override
  String get name => 'temp_file';

  @override
  String get description =>
      '临时文件区（agent 的工作目录）：列文件、读文本、写文本、删文件。'
      '图片、压缩包这类二进制只能列出来和删除，内容读不了，要传走用 temp_upload。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'op': <String, Object?>{
            'type': 'string',
            'enum': <String>['list', 'read', 'write', 'delete'],
          },
          'path': <String, Object?>{
            'type': 'string',
            'description': '临时文件区里的相对路径，可以带子目录，比如 reports/a.md',
          },
          'data': <String, Object?>{'type': 'string', 'description': 'op=write 时的内容'},
        },
        'required': <String>['op'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) {
    final String op = readString(args, 'op');
    return op == 'write' || op == 'delete' ? ToolRisk.write : ToolRisk.read;
  }

  @override
  String summarize(Map<String, Object?> args) {
    final String op = readString(args, 'op');
    final String path = readString(args, 'path');
    return '临时区 $op${path.isEmpty ? '' : ' $path'}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String op = readString(args, 'op').trim();
    final String path = readString(args, 'path').trim();
    try {
      if (op == 'list') {
        final List<TempFile> all = files.list();
        if (all.isEmpty) return const ToolOutcome.success(stdout: '临时文件区还是空的。');
        final StringBuffer b = StringBuffer('临时文件区 ${files.root.path}\n');
        for (final TempFile f in all) {
          b.writeln('${f.path}\t${tempSize(f.size)}\t${f.modified.toIso8601String()}');
        }
        b.write('共 ${all.length} 个，${tempSize(files.totalBytes())}。');
        return ToolOutcome.success(stdout: b.toString());
      }
      if (path.isEmpty) return const ToolOutcome.failure('要给一个 path。');
      if (op == 'read') {
        final String? text = await files.readText(path);
        if (text == null) {
          return ToolOutcome.failure(
            '$path 读不出文本（不存在，或者是二进制文件）。要传走用 temp_upload。',
          );
        }
        return ToolOutcome.success(stdout: text);
      }
      if (op == 'write') {
        final TempFile saved = await files.saveText(path, readString(args, 'data'));
        return ToolOutcome.success(
          stdout: '写好了：${saved.path}，${tempSize(saved.size)}。',
        );
      }
      if (op == 'delete') {
        final bool ok = await files.remove(path);
        return ok
            ? ToolOutcome.success(stdout: '删掉了：$path')
            : ToolOutcome.failure('没有这个文件：$path');
      }
      return ToolOutcome.failure('不认识的 op：$op');
    } catch (e) {
      return ToolOutcome.failure('临时文件区出错了：$e');
    }
  }
}

/// 把临时文件区里的文件传到一台主机上。
class TempUploadTool extends Tool {
  TempUploadTool({required this.files, required this.pool, required this.hosts});

  final TempFiles files;
  final SshPool pool;
  final HostStore hosts;

  @override
  String get name => 'temp_upload';

  @override
  String get description =>
      '把临时文件区里的一个文件传到主机上，覆盖远端同名文件。远端路径以 / 结尾表示放到那个目录里。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'path': <String, Object?>{'type': 'string', 'description': '临时文件区里的相对路径'},
          'host': <String, Object?>{'type': 'string', 'description': '主机名，来自主机列表'},
          'remote': <String, Object?>{
            'type': 'string',
            'description': '远端绝对路径，或者以 / 结尾的目录；留空放 /tmp/ 下',
          },
        },
        'required': <String>['path'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    final String path = readString(args, 'path');
    final String host = readString(args, 'host', fallback: 'default');
    final String remote = readString(args, 'remote');
    return '传 $path → $host:${remote.isEmpty ? '/tmp/' : remote}';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String path = readString(args, 'path').trim();
    final File? local = files.fileOf(path);
    if (local == null) return const ToolOutcome.failure('路径要在临时文件区里面。');
    if (!local.existsSync()) return ToolOutcome.failure('临时区里没有这个文件：$path');
    if (local.lengthSync() > TempFiles.maxBytes) {
      return const ToolOutcome.failure('文件太大，临时文件区只收 8 MB 以内的。');
    }
    final HostEntry? entry = hostForUpload(hosts, readString(args, 'host'));
    if (entry == null) {
      return ToolOutcome.failure(
        readString(args, 'host').isEmpty ? '没有指定主机，而且主机列表里不止一台。' : '主机列表里没有这台。',
      );
    }
    try {
      final TempUpload done =
          await sftpUpload(pool, entry, local, readString(args, 'remote'));
      return ToolOutcome.success(
        stdout: '传好了：${entry.name}:${done.path}（${tempSize(done.bytes)}）',
        meta: <String, Object?>{'host': entry.name, 'bytes': done.bytes},
      );
    } catch (e) {
      return ToolOutcome.failure('传不上去：$e');
    }
  }
}
