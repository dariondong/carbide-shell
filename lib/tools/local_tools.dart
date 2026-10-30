import 'dart:async';
import 'dart:io';

import '../core/memory.dart';
import '../core/models.dart';
import '../core/tools.dart';

/// Run a command on this machine. Only registered on desktop.
class LocalExecTool extends Tool {
  @override
  String get name => 'local_exec';

  @override
  String get description => '在这台电脑上执行一条命令。手机上没有这个工具。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'command': <String, Object?>{'type': 'string'},
        },
        'required': <String>['command'],
      };

  @override
  String summarize(Map<String, Object?> args) => r'local$ ' + readString(args, 'command');

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    if (!context.desktop) return const ToolOutcome.failure('这个平台上不能执行本地命令。');
    final String command = readString(args, 'command').trim();
    if (command.isEmpty) return const ToolOutcome.failure('命令是空的。');
    try {
      final ProcessResult result = Platform.isWindows
          ? await Process.run('cmd', <String>['/c', command]).timeout(context.timeout)
          : await Process.run('sh', <String>['-c', command]).timeout(context.timeout);
      return ToolOutcome.success(
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
        exitCode: result.exitCode,
      );
    } on TimeoutException {
      return const ToolOutcome.failure('命令超时。');
    } catch (e) {
      return ToolOutcome.failure('$e');
    }
  }
}

/// Read a file, or write one inside the agent workspace.
class FileTool extends Tool {
  @override
  String get name => 'file_io';

  @override
  String get description => '读写本机文件。写只能落在 agent 自己的工作目录里。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'op': <String, Object?>{
            'type': 'string',
            'enum': <String>['read', 'write'],
          },
          'path': <String, Object?>{'type': 'string', 'description': '绝对路径，或在工作目录里的相对路径'},
          'data': <String, Object?>{'type': 'string'},
        },
        'required': <String>['op', 'path'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) =>
      readString(args, 'op') == 'write' ? ToolRisk.write : ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) =>
      '${readString(args, 'op')} ${readString(args, 'path')}';

  String _resolve(String raw, ToolContext context) {
    final String path = raw.startsWith('/') || raw.contains(':\\') || raw.contains(':/')
        ? raw
        : '${context.workspace}/$raw';
    return path;
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String raw = readString(args, 'path').trim();
    if (raw.isEmpty) return const ToolOutcome.failure('路径是空的。');
    if (raw.contains('..')) return const ToolOutcome.failure('路径里不许带 .. 。');
    final String path = _resolve(raw, context);
    final File file = File(path);
    final String op = readString(args, 'op');
    try {
      if (op == 'read') {
        if (!file.existsSync()) return ToolOutcome.failure('文件不存在：$path');
        final String text = await file.readAsString();
        return ToolOutcome.success(stdout: text);
      }
      if (op == 'write') {
        final String workspace = context.workspace;
        if (!path.startsWith(workspace)) {
          return ToolOutcome.failure('只能写在 $workspace 里面。');
        }
        await file.parent.create(recursive: true);
        await file.writeAsString(readString(args, 'data'));
        return ToolOutcome.success(stdout: '写好了：$path');
      }
      return ToolOutcome.failure('不认识的 op：$op');
    } catch (e) {
      return ToolOutcome.failure('$e');
    }
  }
}

/// Writes one line into the long-term memory list.
class RememberTool extends Tool {
  RememberTool(this.memory);

  final MemoryStore memory;

  @override
  String get name => 'remember';

  @override
  String get description =>
      '把一件事记进长期记忆，下次开软件还在，也会出现在你的系统提示里。'
      '只是加一条；要改旧的或删掉，用 memory。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'note': <String, Object?>{'type': 'string', 'description': '要记住的一句话'},
          'tag': <String, Object?>{
            'type': 'string',
            'description': '可选分类：偏好 / 主机 / 规则',
          },
        },
        'required': <String>['note'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => '记一笔：${readString(args, 'note')}';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String note = readString(args, 'note').trim();
    if (note.isEmpty) return const ToolOutcome.failure('内容是空的。');
    await memory.add(note, tag: readString(args, 'tag'));
    final StringBuffer b = StringBuffer('记下了。现在一共有 ${memory.length} 条：\n');
    for (final MemoryEntry e in memory.entries.take(5)) {
      b.writeln('- ${e.id}  ${e.tag.isEmpty ? '' : '[${e.tag}] '}${e.text}');
    }
    return ToolOutcome.success(stdout: b.toString());
  }
}
