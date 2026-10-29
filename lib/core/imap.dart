/// 看邮箱：一个够用的 IMAP 客户端。
///
/// 只做三件事：登录、列最近几封、取某一封的全文。993 直接加密，143 明文（一般只在局域网里）。
/// 信箱默认 INBOX，可以换。不 import Flutter，可以单独验。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mime.dart';
import '../version.dart';

/// 一台 IMAP 服务器的设置。账号和密码跟着发信那份走，这里只单列服务器与端口。
class ImapConfig {
  const ImapConfig({
    this.host = '',
    this.port = 993,
    this.secure = true,
    this.user = '',
  });

  final String host;
  final int port;

  /// true 直接 TLS（993），false 明文（143，多用于内网）。
  final bool secure;
  final String user;

  bool get ready => host.trim().isNotEmpty && user.trim().isNotEmpty;

  /// 差哪一项，写在设置页上。
  String get missing {
    if (host.trim().isEmpty) return '没填 IMAP 服务器';
    if (user.trim().isEmpty) return '没填账号';
    return '';
  }

  ImapConfig copyWith({String? host, int? port, bool? secure, String? user}) => ImapConfig(
        host: host ?? this.host,
        port: port ?? this.port,
        secure: secure ?? this.secure,
        user: user ?? this.user,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'host': host,
        'port': port,
        'secure': secure,
        'user': user,
      };

  static ImapConfig fromJson(Map<String, Object?> json) => ImapConfig(
        host: '${json['host'] ?? ''}',
        port: (json['port'] as num?)?.toInt() ?? 993,
        secure: json['secure'] != false,
        user: '${json['user'] ?? ''}',
      );
}

/// 连不上、登录被拒、服务器回了 NO：都抛这个，`message` 是人话。
class ImapError implements Exception {
  const ImapError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 列表里的一条。
class MailSummary {
  const MailSummary({
    this.uid = 0,
    this.from = '',
    this.subject = '',
    this.date = '',
    this.at,
    this.size = 0,
    this.unread = false,
  });

  final int uid;

  /// 发件人原文，`张三 <a@b.com>` 这样。
  final String from;
  final String subject;

  /// 头里那个 Date 原文，解不出时间时兜底显示它。
  final String date;

  /// 服务器收到的时间。
  final DateTime? at;
  final int size;

  /// 没读过。
  final bool unread;

  /// 发件人姓名那部分，没有就退回地址。
  String get fromName {
    final int lt = from.indexOf('<');
    final String name = (lt > 0 ? from.substring(0, lt) : from).trim();
    final String cleaned = name.replaceAll(RegExp('^"|"\$'), '').trim();
    return cleaned.isEmpty ? fromAddress : cleaned;
  }

  String get fromAddress {
    final Match? m = RegExp(r'<([^>]*)>').firstMatch(from);
    if (m != null) return (m.group(1) ?? '').trim();
    return from.trim();
  }

  /// `10-29 16:39` 这样的一小句。
  String get when {
    final DateTime? t = at;
    if (t == null) return date;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// 某一封的全部：头部那几条加能读的正文。
class MailDetail {
  const MailDetail({
    required this.head,
    this.body = '',
    this.html = '',
    this.attachments = 0,
  });

  final MailSummary head;

  /// 能直接读的那一份正文（纯文本优先，没有就把 HTML 转成文字）。
  final String body;
  final String html;

  /// 附件个数，只数不取。
  final int attachments;
}

/// 一个信箱的一次会话：连上、干活、断开。
///
/// 每次调用自己会连一次断一次，省得留半开的连接在后台。
class ImapClient {
  ImapClient(
    this.config,
    this.password, {
    this.mailbox = 'INBOX',
    this.timeout = const Duration(seconds: 25),
  });

  final ImapConfig config;
  final String password;
  final String mailbox;
  final Duration timeout;

  Socket? _socket;
  _Wire? _wire;
  int _seq = 0;

  /// 最近几封。`count` 是封数，最多取 50。
  Future<List<MailSummary>> latest({int count = 15, bool unreadOnly = false}) async {
    final int want = count < 1 ? 1 : (count > 50 ? 50 : count);
    await _open();
    try {
      await _select();
      final List<_Resp> found = await _cmd('UID SEARCH ${unreadOnly ? 'UNSEEN' : 'ALL'}');
      final List<int> uids = <int>[];
      for (final _Resp r in found) {
        final String head = r.text;
        if (!head.toUpperCase().startsWith('SEARCH')) continue;
        final String list = head.substring(6).trim();
        if (list.isEmpty) continue;
        for (final String one in list.split(RegExp(r'\s+'))) {
          final int? n = int.tryParse(one);
          if (n != null) uids.add(n);
        }
      }
      uids.sort();
      if (uids.isEmpty) return const <MailSummary>[];
      final List<int> wanted =
          uids.length > want ? uids.sublist(uids.length - want) : uids;
      final List<_Resp> fetched = await _cmd(
          'UID FETCH ${wanted.join(',')} '
          '(UID FLAGS INTERNALDATE RFC822.SIZE '
          'BODY.PEEK[HEADER.FIELDS (FROM SUBJECT DATE)])');
      final List<MailSummary> out = <MailSummary>[];
      for (final _Resp r in fetched) {
        final String text = r.text;
        if (!text.toUpperCase().contains('FETCH')) continue;
        final int? uid = _intIn(text, r'\bUID (\d+)');
        if (uid == null) continue;
        final Map<String, String> headers = parseHeaderBlock(r.literal);
        out.add(MailSummary(
          uid: uid,
          from: headers['from'] ?? '',
          subject: headers['subject'] ?? '',
          date: headers['date'] ?? '',
          at: serverDate(_strIn(text, 'INTERNALDATE "([^"]*)"')),
          size: _intIn(text, r'RFC822\.SIZE (\d+)') ?? 0,
          unread: !RegExp(r'FLAGS \([^)]*\\Seen').hasMatch(text),
        ));
      }
      out.sort((MailSummary a, MailSummary b) => a.uid.compareTo(b.uid));
      return out;
    } finally {
      await close();
    }
  }

  /// 看一封。正文太长由调用方去截。
  Future<MailDetail> read(int uid) async {
    if (uid <= 0) throw const ImapError('uid 不对');
    await _open();
    try {
      await _select();
      final List<_Resp> fetched = await _cmd('UID FETCH $uid (UID BODY.PEEK[])');
      for (final _Resp r in fetched) {
        final String text = r.text;
        if (!text.toUpperCase().contains('FETCH')) continue;
        final ParsedMail mail = parseMail(r.literal);
        final Map<String, String> headers = mail.headers;
        return MailDetail(
          head: MailSummary(
            uid: uid,
            from: headers['from'] ?? '',
            subject: headers['subject'] ?? '',
            date: headers['date'] ?? '',
            at: serverDate(_strIn(text, 'INTERNALDATE "([^"]*)"')),
            size: r.literal.length,
            unread: !RegExp(r'FLAGS \([^)]*\\Seen').hasMatch(text),
          ),
          body: mail.readable,
          html: mail.html,
          attachments: mail.attachments,
        );
      }
      throw ImapError('信箱里没有 uid $uid 这一封了');
    } finally {
      await close();
    }
  }

  /// 只测连通与登录，不发别的。
  Future<String> ping() async {
    await _open();
    try {
      await _cmd('LIST "" ""');
      return '连上了';
    } finally {
      await close();
    }
  }

  Future<void> _open() async {
    if (!config.ready) {
      throw ImapError(config.missing.isEmpty ? 'IMAP 没配全' : config.missing);
    }
    final Socket raw = await Socket.connect(config.host.trim(), config.port, timeout: timeout);
    raw.setOption(SocketOption.tcpNoDelay, true);
    _socket = config.secure
        ? await SecureSocket.secure(raw, host: config.host.trim()).timeout(timeout)
        : raw;
    _wire = _Wire(_socket!);
    final String hello = await _wire!.line(timeout);
    final String upper = hello.toUpperCase();
    if (!upper.startsWith('* OK') && !upper.startsWith('* PREAUTH')) {
      throw ImapError('服务器没打招呼：${_plain(hello)}');
    }
    if (upper.startsWith('* PREAUTH')) return; // 已经认过身份了
    // 163 / 126 这类服务商要求先报一句 ID，不认识的服务器回 BAD，忽略就行。
    try {
      await _cmd('ID ("name" "Carbide Shell" "version" "$kAppVersion" '
          '"vendor" "aprsnet.cn")');
    } on ImapError {
      // 不认这条就算了，接着登录。
    }
    await _cmd('LOGIN ${_quote(config.user)} ${_quote(password)}');
  }

  Future<void> _select() async {
    await _cmd('SELECT ${_quote(mailbox)}');
  }

  Future<void> close() async {
    final _Wire? wire = _wire;
    _wire = null;
    if (wire != null) {
      try {
        await _cmdRaw(wire, 'LOGOUT').timeout(const Duration(seconds: 3));
      } catch (_) {
        // 收不了尾就算了，下面直接断。
      }
    }
    try {
      _socket?.destroy();
    } catch (_) {
      // ignore
    }
    _socket = null;
  }

  Future<List<_Resp>> _cmd(String text) {
    final _Wire? wire = _wire;
    if (wire == null) throw const ImapError('还没连上');
    return _cmdRaw(wire, text);
  }

  /// 发一条命令，读到带标记的那行收尾。中间的 `* …` 一条一条留下来。
  Future<List<_Resp>> _cmdRaw(_Wire wire, String text) async {
    final String tag = 'c${_seq++}';
    await wire.write('$tag $text\r\n');
    final List<_Resp> out = <_Resp>[];
    _Resp? cur;
    while (true) {
      final String line = await wire.line(timeout);
      if (line.startsWith('$tag ')) {
        if (cur != null) out.add(cur);
        final String rest = line.substring(tag.length + 1).trim();
        final String code = rest.isEmpty ? '' : rest.split(' ').first.toUpperCase();
        if (code != 'OK') throw ImapError(_plain(rest));
        return out;
      }
      if (line.startsWith('* ')) {
        if (cur != null) out.add(cur);
        cur = _Resp(line.substring(2));
      } else {
        final String tail = line.trim();
        if (tail.isNotEmpty) {
          cur ??= _Resp('');
          cur.append(tail);
        }
      }
      // 行尾挂着 {123} 的话，后面紧跟这么多个字节的内容，算这一条响应的字面量。
      final int literal = _literalSize(line);
      if (literal > 0) {
        final List<int> bytes = await wire.take(literal, timeout);
        cur ??= _Resp('');
        cur.addLiteral(latin1.decode(bytes, allowInvalid: true));
      }
    }
  }
}

/// 一条读进来的响应：文字部分加它带的那段字面量。
class _Resp {
  _Resp(String head) : _head = StringBuffer(head);

  final StringBuffer _head;
  final StringBuffer _literal = StringBuffer();

  void append(String text) {
    _head.write(' ');
    _head.write(text);
  }

  void addLiteral(String text) => _literal.write(text);

  String get text => _head.toString();
  String get literal => _literal.toString();
}

/// 一条连接：读一行、读一段字节。
class _Wire {
  _Wire(this._socket) : _lines = StreamIterator<List<int>>(_socket);

  final Socket _socket;
  final StreamIterator<List<int>> _lines;
  final List<int> _buffer = <int>[];
  int _at = 0;

  Future<void> write(String text) async {
    _socket.write(text);
    await _socket.flush();
  }

  Future<List<int>> take(int n, Duration timeout) async {
    while (_buffer.length - _at < n) {
      if (!await _lines.moveNext().timeout(timeout)) {
        throw const ImapError('连接被服务器关掉了');
      }
      _buffer.addAll(_lines.current);
    }
    final List<int> out = _buffer.sublist(_at, _at + n);
    _at += n;
    _trim();
    return out;
  }

  /// 读到换行为止，去掉行尾的 `\r`。
  Future<String> line(Duration timeout) async {
    while (true) {
      final int nl = _buffer.indexOf(10, _at);
      if (nl >= 0) {
        final String text =
            latin1.decode(_buffer.sublist(_at, nl), allowInvalid: true).replaceAll('\r', '');
        _at = nl + 1;
        _trim();
        return text;
      }
      if (!await _lines.moveNext().timeout(timeout)) {
        throw const ImapError('连接被服务器关掉了');
      }
      _buffer.addAll(_lines.current);
    }
  }

  /// 读过的部分别一直攒着。
  void _trim() {
    if (_at >= 65536) {
      _buffer.removeRange(0, _at);
      _at = 0;
    }
  }
}

/// 行尾的 `{123}` / `{123+}`，后面紧跟这么多个字节的字面量。
int _literalSize(String line) {
  final Match? m = RegExp(r'\{(\d+)\+?\}$').firstMatch(line);
  if (m == null) return 0;
  return int.tryParse(m.group(1) ?? '') ?? 0;
}

int? _intIn(String text, String pattern) {
  final Match? m = RegExp(pattern).firstMatch(text);
  if (m == null) return null;
  return int.tryParse(m.group(1) ?? '');
}

String _strIn(String text, String pattern) {
  final Match? m = RegExp(pattern).firstMatch(text);
  return m == null ? '' : (m.group(1) ?? '');
}

/// IMAP 的日期写法：`29-Oct-2026 16:39:00 +0800`。
const List<String> _months = <String>[
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

DateTime? serverDate(String raw) {
  final Match? m = RegExp(
          r'(\d{1,2})-([A-Za-z]{3})-(\d{4}) (\d{1,2}):(\d{2}):(\d{2}) ([+-])(\d{2})(\d{2})')
      .firstMatch(raw);
  if (m == null) return null;
  final int month = _months.indexOf((m.group(2) ?? '').toLowerCase()) + 1;
  if (month == 0) return null;
  int pick(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  final String sign = m.group(7) ?? '+';
  final int offset = pick(8) * 3600 + pick(9) * 60;
  final DateTime utc =
      DateTime.utc(pick(3), month, pick(1), pick(4), pick(5), pick(6));
  return utc.subtract(Duration(seconds: sign == '-' ? -offset : offset)).toLocal();
}

/// `"…"` 里别让引号和反斜杠把命令切断。
String _quote(String text) {
  final String escaped = text.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  return '"$escaped"';
}

/// 服务器回的长句里挑一句能看懂的说出去。
String _plain(String reply) {
  final String text = repairByteText(reply.trim());
  if (text.length <= 3) return '服务器回了「$text」';
  return text.substring(3).trim();
}
