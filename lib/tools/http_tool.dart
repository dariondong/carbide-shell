import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/models.dart';
import '../core/tools.dart';
import '../data/settings.dart';

/// Any HTTP request, but only to domains the user allowed.
class HttpTool extends Tool {
  HttpTool(this.settings);

  final SettingsStore settings;

  @override
  String get name => 'http_request';

  @override
  String get description =>
      '发一个 HTTP 请求。设置里加过的域名直接发；没加过的会先问一句，批准了这一次才发。'
      '返回状态码、头前几行和正文。';

  /// 域名在允许列表里没有，就要问一句才发。
  bool _allowed(String host) => settings.value.allowedDomains
      .any((String d) => host == d || host.endsWith('.$d'));

  String _hostOf(Map<String, Object?> args) =>
      Uri.tryParse(readString(args, 'url').trim())?.host ?? '';

  @override
  Map<String, Object?> get schema => <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'method': <String, Object?>{
            'type': 'string',
            'enum': <String>['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD'],
          },
          'url': <String, Object?>{'type': 'string'},
          'headers': <String, Object?>{'type': 'object'},
          'body': <String, Object?>{'type': 'string'},
        },
        'required': <String>['url'],
      };

  @override
  ToolRisk classify(Map<String, Object?> args) {
    final String method = readString(args, 'method', fallback: 'GET').toUpperCase();
    final String host = _hostOf(args);
    // 没加过的域名一律当成写操作：审批档再宽也会先问一次。
    if (host.isEmpty || !_allowed(host)) return ToolRisk.write;
    return method == 'GET' || method == 'HEAD' ? ToolRisk.read : ToolRisk.write;
  }

  @override
  String summarize(Map<String, Object?> args) {
    final String host = _hostOf(args);
    final String line =
        '${readString(args, 'method', fallback: 'GET').toUpperCase()} ${readString(args, 'url')}';
    if (host.isNotEmpty && !_allowed(host)) return '$line（$host 不在允许列表）';
    return line;
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final String raw = readString(args, 'url').trim();
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasAuthority) return const ToolOutcome.failure('网址不对。');
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return const ToolOutcome.failure('只支持 http 和 https。');
    }
    final bool allowed = _allowed(uri.host) || context.granted;
    if (!allowed) {
      return ToolOutcome.failure('${uri.host} 不在允许列表里。先到设置里加上它，'
          '或者让用户批准这一次。');
    }

    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final String method = readString(args, 'method', fallback: 'GET').toUpperCase();
      final HttpClientRequest req = await client.openUrl(method, uri);
      final Object? headers = args['headers'];
      if (headers is Map) {
        headers.forEach((Object? k, Object? v) => req.headers.set('$k', '$v'));
      }
      final String body = readString(args, 'body');
      if (body.isNotEmpty) {
        req.headers.contentType ??= ContentType.text;
        req.write(body);
      }
      final HttpClientResponse res = await req.close().timeout(context.timeout);
      final StringBuffer head = StringBuffer();
      head.writeln('HTTP ${res.statusCode} ${res.reasonPhrase}');
      res.headers.forEach((String k, List<String> v) => head.writeln('$k: ${v.join(', ')}'));
      final String type = res.headers.contentType?.mimeType ?? '';
      final List<int> bytes = <int>[];
      await for (final List<int> chunk in res) {
        bytes.addAll(chunk);
        if (bytes.length > 262144) break;
      }
      final bool textish = type.isEmpty ||
          type.startsWith('text/') ||
          type.contains('json') ||
          type.contains('xml') ||
          type.contains('javascript');
      final String payload = textish
          ? utf8.decode(bytes, allowMalformed: true)
          : '<${bytes.length} 字节的 $type，没有带进上下文>';
      return ToolOutcome.success(
        stdout: '$head\n$payload',
        meta: <String, Object?>{'status': res.statusCode, 'bytes': bytes.length},
      );
    } on TimeoutException {
      return const ToolOutcome.failure('请求超时。');
    } catch (e) {
      return ToolOutcome.failure('$e');
    } finally {
      client.close(force: true);
    }
  }
}
