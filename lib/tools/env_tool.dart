import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
import '../core/tools.dart';
import '../data/env_keys.dart';
import '../data/settings.dart';

/// 环境密钥这一组工具。
///
/// 三条规矩：值只进安全存储、进模型眼睛的只有名字和末尾两位；写入和删除一律要用户点批准；
/// 要用它的时候不把值交出去，而是由本机带着这把密钥去请求一次。

/// `env_list`：有哪些钥匙，值只给末尾两位。
class EnvListTool extends Tool {
  EnvListTool(this.book);

  final EnvBook book;

  @override
  String get name => 'env_list';

  @override
  String get description =>
      '列出本机存着的环境密钥：名字、说明、末尾两位。值的全文不会给你，'
      '要拿它去请求就先记下名字，用 env_request。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{},
      };

  @override
  ToolRisk get risk => ToolRisk.read;

  @override
  String summarize(Map<String, Object?> args) => '看看有哪些环境密钥';

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    if (book.all.isEmpty) {
      return const ToolOutcome.success(
          stdout: '还没有存过环境密钥。要存就在设置 → 环境密钥里加，或者用 env_set（要用户批准）。');
    }
    final Map<String, String> masked = await book.masked();
    final StringBuffer b = StringBuffer();
    for (final EnvKey k in book.all) {
      b.write('- ${k.name}（${masked[k.name] ?? '未设'}）');
      if (k.note.isNotEmpty) b.write('：${k.note}');
      b.writeln();
    }
    return ToolOutcome.success(stdout: b.toString().trimRight());
  }
}

/// `env_set`：AI 代写一把。值要用户点批准才存。
class EnvSetTool extends Tool {
  EnvSetTool(this.book);

  final EnvBook book;

  @override
  String get name => 'env_set';

  @override
  String get description =>
      '把一把环境密钥写进本机的安全存储。用户点批准才真的存。'
      '名字用大写字母、数字和下划线，像 GITHUB_TOKEN。同名再写一次就是更新。'
      '值写进 body 之后就不用再复述它，也不要把它写进回答里。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{
            'type': 'string',
            'description': '名字，大写字母、数字、下划线，例如 GITHUB_TOKEN',
          },
          'value': <String, Object?>{'type': 'string', 'description': '密钥本身'},
          'note': <String, Object?>{'type': 'string', 'description': '它是干什么用的，一句话'},
        },
        'required': <String>['name', 'value'],
      };

  @override
  bool get alwaysAsk => true;

  @override
  String summarize(Map<String, Object?> args) {
    final String name = readString(args, 'name').trim();
    return name.isEmpty ? '写入一把环境密钥' : '写入环境密钥 $name';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String name = readString(args, 'name').trim();
    final String value = readString(args, 'value');
    if (!validEnvName(name)) {
      return const ToolOutcome.failure(
          '名字要全用大写字母、数字和下划线，并且不以数字开头，例如 GITHUB_TOKEN。');
    }
    if (value.trim().isEmpty) return const ToolOutcome.failure('值是空的，没存。');
    await book.set(name, value, note: readString(args, 'note').trim(), by: 'ai');
    return ToolOutcome.success(
        stdout: '存好了：$name。值只在安全存储里，这次对话的记录里不会出现它。');
  }
}

/// `env_delete`：删一把。也要批准。
class EnvDeleteTool extends Tool {
  EnvDeleteTool(this.book);

  final EnvBook book;

  @override
  String get name => 'env_delete';

  @override
  String get description => '删掉一把环境密钥连同它的值。用户点批准才删。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string'},
        },
        'required': <String>['name'],
      };

  @override
  bool get alwaysAsk => true;

  @override
  String summarize(Map<String, Object?> args) {
    final String name = readString(args, 'name').trim();
    return name.isEmpty ? '删掉一把环境密钥' : '删掉环境密钥 $name';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String name = readString(args, 'name').trim();
    if (book.byName(name) == null) {
      return ToolOutcome.failure('没有叫 $name 的密钥。要看得用 env_list。');
    }
    await book.remove(name, by: 'ai');
    return ToolOutcome.success(stdout: '删掉了 $name。');
  }
}

/// `env_request`：本机带着一把密钥发一次请求，值不给模型看。
class EnvRequestTool extends Tool {
  EnvRequestTool(this.book, this.settings);

  final EnvBook book;
  final SettingsStore settings;

  @override
  String get name => 'env_request';

  @override
  String get description =>
      '本机带着存好的环境密钥发一次 HTTP 请求：密钥放在指定的头里，值的全文不会出现在结果里。'
      '只能访问设置里允许的域名。返回状态码和正文前一段。';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'name': <String, Object?>{'type': 'string', 'description': '密钥名，例如 GITHUB_TOKEN'},
          'url': <String, Object?>{'type': 'string'},
          'method': <String, Object?>{
            'type': 'string',
            'enum': <String>['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'],
          },
          'header': <String, Object?>{
            'type': 'string',
            'description': '密钥放在哪个头里，默认 Authorization',
          },
          'prefix': <String, Object?>{
            'type': 'string',
            'description': '头里密钥前面那段，默认 Bearer 加一个空格；不需要就填空串',
          },
          'body': <String, Object?>{'type': 'string'},
        },
        'required': <String>['name', 'url'],
      };

  @override
  bool get alwaysAsk => true;

  @override
  String summarize(Map<String, Object?> args) {
    final String name = readString(args, 'name').trim();
    final String method = readString(args, 'method', fallback: 'GET').toUpperCase();
    return '$method ${readString(args, 'url')}（带 $name）';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String name = readString(args, 'name').trim();
    final EnvKey? key = book.byName(name);
    if (key == null) return ToolOutcome.failure('没有叫 $name 的密钥。要看得用 env_list。');
    final String value = await book.value(name);
    if (value.isEmpty) return ToolOutcome.failure('$name 没有值，先在设置里填上。');
    final Uri? uri = Uri.tryParse(readString(args, 'url').trim());
    if (uri == null || !uri.hasAuthority) return const ToolOutcome.failure('网址不对。');
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return const ToolOutcome.failure('只支持 http 和 https。');
    }
    final bool allowed = settings.value.allowedDomains
        .any((String d) => uri.host == d || uri.host.endsWith('.$d'));
    if (!allowed) {
      return ToolOutcome.failure('${uri.host} 不在允许列表里。先到设置 → 网络里加上它。');
    }
    final String header = readString(args, 'header', fallback: 'Authorization').trim();
    final String prefix = args['prefix'] is String
        ? '${args['prefix']}'
        : 'Bearer ';
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final String method = readString(args, 'method', fallback: 'GET').toUpperCase();
      final HttpClientRequest req = await client.openUrl(method, uri);
      if (header.isNotEmpty) req.headers.set(header, '$prefix$value');
      final String body = readString(args, 'body');
      if (body.isNotEmpty) {
        req.headers.contentType ??= ContentType.json;
        req.write(body);
      }
      final HttpClientResponse res = await req.close().timeout(context.timeout);
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > 65536) break;
      }
      String text = utf8.decode(bytes, allowMalformed: true);
      // 万一对方把密钥回显在正文里，也抹掉再交出去。
      if (text.contains(value)) text = text.replaceAll(value, maskEnvValue(value));
      if (text.length > 2000) text = '${text.substring(0, 2000)}…';
      return ToolOutcome.success(stdout: 'HTTP ${res.statusCode}\n$text');
    } catch (e) {
      return ToolOutcome.failure('请求没发成：$e');
    } finally {
      client.close(force: true);
    }
  }
}
