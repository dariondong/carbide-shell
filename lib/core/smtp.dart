/// 发一封邮件：一个够用的 SMTP 客户端。
///
/// 只做两件事：直接加密连（465）和不加密连（25，一般只在局域网里）。登录走 AUTH LOGIN，
/// 服务器不认就试 AUTH PLAIN。不 import Flutter，可以单独测报文拼装。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 一台 SMTP 服务器的设置。
class SmtpConfig {
  const SmtpConfig({
    this.enabled = false,
    this.host = '',
    this.port = 465,
    this.secure = true,
    this.user = '',
    this.from = '',
    this.to = '',
    this.html = true,
  });

  final bool enabled;
  final String host;
  final int port;

  /// true 直接 TLS（465），false 明文（25，多用于内网中转）。
  final bool secure;
  final String user;

  /// 带一份 HTML 排版的正文，同时留一份纯文本给不认 HTML 的客户端。
  final bool html;

  /// 发件人地址。多数服务器要求它和账号一致。
  final String from;

  /// 收件人，多个用逗号或者空格分开。
  final String to;

  List<String> get recipients => to
      .split(RegExp(r'[,;\s]+'))
      .map((String s) => s.trim())
      .where((String s) => s.contains('@'))
      .toList();

  /// 开关开着，而且地址、发件人、收件人都写了。
  bool get ready =>
      enabled && host.trim().isNotEmpty && from.contains('@') && recipients.isNotEmpty;

  /// 差哪一项，写在设置页上。
  String get missing {
    if (!enabled) return '没打开';
    if (host.trim().isEmpty) return '没填服务器';
    if (!from.contains('@')) return '没填发件人';
    if (recipients.isEmpty) return '没填收件人';
    return '';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'enabled': enabled,
        'host': host,
        'port': port,
        'secure': secure,
        'user': user,
        'from': from,
        'to': to,
        'html': html,
      };

  static SmtpConfig fromJson(Map<String, Object?> json) => SmtpConfig(
        enabled: json['enabled'] == true,
        host: '${json['host'] ?? ''}',
        port: (json['port'] as num?)?.toInt() ?? 465,
        secure: json['secure'] != false,
        user: '${json['user'] ?? ''}',
        from: '${json['from'] ?? ''}',
        to: '${json['to'] ?? ''}',
        html: json['html'] != false,
      );
}

/// 发出去成没成，没成的原因。
class SmtpResult {
  const SmtpResult({this.ok = false, this.error = ''});

  final bool ok;
  final String error;
}

class SmtpError implements Exception {
  const SmtpError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 发一封邮件。[password] 留空表示服务器不要登录。
///
/// [html] 非空就多带一份 HTML 版；不填就是纯文本一封。
Future<SmtpResult> sendMail(
  SmtpConfig config,
  String password, {
  required String subject,
  required String body,
  String html = '',
  Duration timeout = const Duration(seconds: 25),
}) async {
  if (!config.ready) {
    return SmtpResult(error: config.missing.isEmpty ? '邮件没配全' : config.missing);
  }
  Socket? socket;
  try {
    final Socket raw = await Socket.connect(config.host.trim(), config.port,
        timeout: timeout);
    raw.setOption(SocketOption.tcpNoDelay, true);
    socket = config.secure
        ? await SecureSocket.secure(raw, host: config.host.trim()).timeout(timeout)
        : raw;
    final _Session session = _Session(socket);
    await session.reply(timeout: timeout).then((String r) => _expect(r, <String>['220']));
    await session.command('EHLO carbide-shel', timeout: timeout);
    if (config.user.trim().isNotEmpty && password.isNotEmpty) {
      await session.auth(config.user.trim(), password, timeout: timeout);
    }
    await session.command('MAIL FROM:<${config.from.trim()}>', timeout: timeout);
    for (final String to in config.recipients) {
      await session.command('RCPT TO:<$to>', timeout: timeout, allow: <String>['250', '251']);
    }
    await session.command('DATA', timeout: timeout, allow: <String>['354']);
    await session.write(composeMessage(config, subject, body, html: html),
        timeout: timeout);
    _expect(await session.reply(timeout: timeout), <String>['250']);
    try {
      await session.command('QUIT', timeout: timeout, allow: <String>['221']);
    } catch (_) {
      // 收尾那句回不回都不影响这封信已经收下。
    }
    return const SmtpResult(ok: true);
  } on SmtpError catch (e) {
    return SmtpResult(error: e.message);
  } on TimeoutException {
    return SmtpResult(error: '${config.host}:${config.port} 一直没回音');
  } catch (e) {
    return SmtpResult(error: '$e'.replaceFirst('Exception: ', ''));
  } finally {
    try {
      socket?.destroy();
    } catch (_) {
      // ignore
    }
  }
}

/// 两段之间的分界线。两段都是 base64，这串字不可能出现在正文里。
const String kMailBoundary = '=_carbide_shell_1';

/// 信的内容：头 + base64 正文，中文不用管编码。
///
/// [html] 非空时写成 multipart/alternative：先纯文本，后 HTML，
/// 由收信的客户端自己挑一份显示。
String composeMessage(SmtpConfig config, String subject, String body,
    {String html = ''}) {
  final String subjectText = _encodeHeader(subject);
  final StringBuffer b = StringBuffer()
    ..write('From: <${config.from.trim()}>\r\n')
    ..write('To: <${config.recipients.join('>, <')}>\r\n')
    ..write('Subject: $subjectText\r\n')
    ..write('Date: ${HttpDate.format(DateTime.now().toUtc())}\r\n')
    ..write('MIME-Version: 1.0\r\n');
  final String rich = html.trim();
  if (rich.isEmpty) {
    b
      ..write('Content-Type: text/plain; charset=UTF-8\r\n')
      ..write('Content-Transfer-Encoding: base64\r\n')
      ..write('\r\n')
      ..write(_base64Block(body));
  } else {
    b
      ..write('Content-Type: multipart/alternative; boundary="$kMailBoundary"\r\n')
      ..write('\r\n')
      ..write('--$kMailBoundary\r\n')
      ..write('Content-Type: text/plain; charset=UTF-8\r\n')
      ..write('Content-Transfer-Encoding: base64\r\n')
      ..write('\r\n')
      ..write(_base64Block(body))
      ..write('--$kMailBoundary\r\n')
      ..write('Content-Type: text/html; charset=UTF-8\r\n')
      ..write('Content-Transfer-Encoding: base64\r\n')
      ..write('\r\n')
      ..write(_base64Block(rich))
      ..write('--$kMailBoundary--\r\n');
  }
  // DATA 的结束标记，前面必须是空行。
  if (!b.toString().endsWith('\r\n')) b.write('\r\n');
  b.write('.\r\n');
  return b.toString();
}

/// base64 折到 76 列，每段后面都带回车。
String _base64Block(String text) => base64.encode(utf8.encode(text)).replaceAllMapped(
      RegExp(r'.{1,76}'),
      (Match m) => '${m.group(0)}\r\n',
    );

/// 主题里的中文走 RFC 2047，一行放得下就不用折。
String _encodeHeader(String text) {
  if (text.codeUnits.every((int c) => c < 128)) return text;
  return '=?UTF-8?B?${base64.encode(utf8.encode(text))}?=';
}

void _expect(String reply, List<String> codes) {
  final String code = reply.length >= 3 ? reply.substring(0, 3) : reply;
  if (codes.contains(code)) return;
  throw SmtpError(_plain(reply));
}

/// 服务器回的长句里挑一句能看懂的说出去。
String _plain(String reply) {
  final String text = reply.trim();
  if (text.length <= 3) return '服务器回了「$text」';
  return text.substring(3).trim();
}

/// 一条连接：发一句、读回一句。
class _Session {
  _Session(this._socket) : _lines = StreamIterator<List<int>>(_socket);

  final Socket _socket;
  final StreamIterator<List<int>> _lines;
  final List<int> _buffer = <int>[];

  Future<void> write(String data, {Duration? timeout}) async {
    _socket.write(data);
    final Future<void> flushing = _socket.flush();
    if (timeout != null) {
      await flushing.timeout(timeout);
    } else {
      await flushing;
    }
  }

  /// 读一次完整的回话（多行只取最后一行）。
  Future<String> reply({Duration? timeout}) async {
    Future<String> one = _line();
    String line = timeout == null ? await one : await one.timeout(timeout);
    while (line.length > 3 && line[3] == '-') {
      one = _line();
      line = timeout == null ? await one : await one.timeout(timeout);
    }
    return line;
  }

  Future<String> _line() async {
    while (true) {
      final int nl = _buffer.indexOf(10);
      if (nl >= 0) {
        final List<int> raw = _buffer.sublist(0, nl);
        _buffer.removeRange(0, nl + 1);
        return utf8.decode(raw, allowMalformed: true).replaceAll('\r', '');
      }
      if (!await _lines.moveNext()) {
        throw const SmtpError('连接被服务器关掉了');
      }
      _buffer.addAll(_lines.current);
    }
  }

  Future<String> command(
    String text, {
    Duration? timeout,
    List<String> allow = const <String>['250'],
  }) async {
    await write('$text\r\n', timeout: timeout);
    final String reply = await this.reply(timeout: timeout);
    _expect(reply, allow);
    return reply;
  }

  /// 先试 AUTH LOGIN，服务器不认再试 AUTH PLAIN。
  Future<void> auth(String user, String password, {Duration? timeout}) async {
    await write('AUTH LOGIN\r\n', timeout: timeout);
    String reply = await this.reply(timeout: timeout);
    if (reply.startsWith('334')) {
      await write('${base64.encode(utf8.encode(user))}\r\n', timeout: timeout);
      reply = await this.reply(timeout: timeout);
      if (!reply.startsWith('334')) throw SmtpError('账号没被接受：${_plain(reply)}');
      await write('${base64.encode(utf8.encode(password))}\r\n', timeout: timeout);
      reply = await this.reply(timeout: timeout);
      if (reply.startsWith('235')) return;
      throw SmtpError('登录被拒：${_plain(reply)}');
    }
    final String plain = base64.encode(utf8.encode('\u0000$user\u0000$password'));
    await write('AUTH PLAIN $plain\r\n', timeout: timeout);
    reply = await this.reply(timeout: timeout);
    if (reply.startsWith('235')) return;
    throw SmtpError('登录被拒：${_plain(reply)}');
  }
}
