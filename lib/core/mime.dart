/// 读一封邮件：拆头部、挑正文、按编码还原。
///
/// 只做收信要用的那一层：头部折行、`=?UTF-8?B?…?=` 这种写法、multipart 里挑一份能读的正文、
/// base64 与 quoted-printable。附件只数个数，不往外掏。
///
/// 传进来的字符串按「一个字符就是一个字节」处理（读 socket 时用 latin1 落的），
/// 这样每段自己的 charset 才有意义。
library;

import 'dart:convert';

import 'gbk.dart';

/// 一封拆开的邮件。键都是小写的头名。
class ParsedMail {
  const ParsedMail({
    required this.headers,
    this.text = '',
    this.html = '',
    this.attachments = 0,
  });

  final Map<String, String> headers;

  /// text/plain 那一份。
  final String text;

  /// text/html 那一份。
  final String html;

  /// 数了但没解开的附件个数。
  final int attachments;

  String get subject => headers['subject'] ?? '';
  String get from => headers['from'] ?? '';
  String get to => headers['to'] ?? '';
  String get date => headers['date'] ?? '';

  /// 能直接给人看的那一份：纯文本优先，没有就把 HTML 转成文字。
  String get readable {
    final String plain = text.trim();
    if (plain.isNotEmpty) return plain;
    return htmlToText(html).trim();
  }
}

/// 一整封信（头 + 正文）拆成 [ParsedMail]。
ParsedMail parseMail(String raw) {
  final _Acc acc = _Acc();
  final String text = raw.replaceAll('\r\n', '\n');
  final int split = text.indexOf('\n\n');
  final String headBlock = split < 0 ? text : text.substring(0, split);
  final String body = split < 0 ? '' : text.substring(split + 2);
  final Map<String, String> headers = parseHeaders(headBlock);
  _walk(headers, body, acc);
  return ParsedMail(
    headers: headers,
    text: acc.text.toString(),
    html: acc.html.toString(),
    attachments: acc.attachments,
  );
}

/// 只要头部的那一段（列表页用）。
Map<String, String> parseHeaderBlock(String raw) {
  final String text = raw.replaceAll('\r\n', '\n');
  final int split = text.indexOf('\n\n');
  return parseHeaders(split < 0 ? text : text.substring(0, split));
}

/// 头部块 → 小写键的映射。折行接回去，`=?…?=` 解开。
Map<String, String> parseHeaders(String block) {
  final Map<String, String> out = <String, String>{};
  final List<String> lines = <String>[];
  for (final String line in block.split('\n')) {
    if (line.isEmpty) continue;
    if (line.startsWith(' ') || line.startsWith('\t')) {
      if (lines.isNotEmpty) {
        lines[lines.length - 1] = '${lines.last} ${line.trim()}';
      }
      continue;
    }
    lines.add(line);
  }
  for (final String line in lines) {
    final int colon = line.indexOf(':');
    if (colon <= 0) continue;
    final String key = line.substring(0, colon).trim().toLowerCase();
    final String value = decodeWord(line.substring(colon + 1).trim());
    if (key.isEmpty || out.containsKey(key)) continue;
    out[key] = value;
  }
  return out;
}

/// 解 `=?UTF-8?B?…?=` / `=?GBK?Q?…?=` 这种写法，别的地方原样留着。
String decodeWord(String text) {
  if (!text.contains('=?')) return repairByteText(text);
  final StringBuffer out = StringBuffer();
  int at = 0;
  for (final Match m in _encodedWord.allMatches(text)) {
    if (m.start > at) out.write(repairByteText(text.substring(at, m.start)));
    final String charset = m.group(1) ?? 'utf-8';
    final String how = (m.group(2) ?? 'B').toUpperCase();
    final String payload = m.group(3) ?? '';
    if (how == 'B') {
      out.write(_decodeBase64(payload, charset));
    } else {
      out.write(_decodeQuoted(_percentToQuestion(payload), charset));
    }
    at = m.end;
  }
  if (at < text.length) out.write(repairByteText(text.substring(at)));
  return out.toString();
}

final RegExp _encodedWord = RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]*)\?=');

/// 把一段字节按 charset 变成字符串。
///
/// 认三种：GBK 家族（gbk / gb2312 / gb18030 / cp936）、Latin-1 家族、其余按 UTF-8。
/// 没写 charset 的，先严格按 UTF-8 试一遍，坏字节再让 GBK 顶上去：中文的旧信多半是 GBK，
/// 而 GBK 几乎什么字节都能凑出字来，所以只有整段解得干干净净才换用。
String decodeBytesText(String raw, String charset) {
  final List<int> bytes = _bytesOf(raw);
  final String cs = charset.trim().toLowerCase();
  if (isGbkCharset(cs)) return decodeGbk(bytes);
  final String? strict = _utf8OrNull(bytes);
  if (cs.contains('8859') || cs.contains('latin') || cs == 'us-ascii' || cs == 'ascii') {
    return strict ?? latin1.decode(bytes, allowInvalid: true);
  }
  if (strict != null) return strict;
  if (!cs.contains('utf')) {
    final String gbk = decodeGbk(bytes);
    if (!gbk.contains('\uFFFD')) return gbk;
  }
  return utf8.decode(bytes, allowMalformed: true);
}

/// `gbk` `gb2312` `gb18030` `cp936` `x-gbk` `euc-cn` 都算同一族。
bool isGbkCharset(String charset) {
  final String cs = charset.trim().toLowerCase();
  return cs.contains('gbk') ||
      cs.contains('gb2312') ||
      cs.contains('gb18030') ||
      cs.contains('cp936') ||
      cs.contains('euc-cn');
}

String? _utf8OrNull(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// base64 正文 → 字符串。
String decodeBase64Body(String body, String charset) =>
    _decodeBase64(body, charset);

/// quoted-printable 正文 → 字符串。
String decodeQuotedPrintableBody(String body, String charset) =>
    _decodeQuoted(body, charset);

/// HTML 里能读出来的那些字。标签去掉，块级元素换成换行，实体解开。
String htmlToText(String html) {
  if (html.trim().isEmpty) return '';
  String s = html
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
      .replaceAll(RegExp(r'<(script|style)[\s\S]*?</\1>', caseSensitive: false), '');
  s = s.replaceAll(
      RegExp(r'<br\s*/?>|</p>|</div>|</tr>|</li>|</h[1-6]>', caseSensitive: false), '\n');
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  s = unescapeHtml(s);
  s = s.replaceAll(RegExp(r'[ \t\u00a0]+'), ' ');
  s = s.replaceAll(RegExp(r' *\n *'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// `&nbsp;` `&amp;` `&#39;` 这些换回字符。
String unescapeHtml(String text) {
  if (!text.contains('&')) return text;
  return text.replaceAllMapped(RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'), (Match m) {
    final String body = m.group(1) ?? '';
    if (body.startsWith('#x') || body.startsWith('#X')) {
      final int? code = int.tryParse(body.substring(2), radix: 16);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    }
    if (body.startsWith('#')) {
      final int? code = int.tryParse(body.substring(1));
      return code == null ? m.group(0)! : String.fromCharCode(code);
    }
    switch (body.toLowerCase()) {
      case 'nbsp':
        return ' ';
      case 'amp':
        return '&';
      case 'lt':
        return '<';
      case 'gt':
        return '>';
      case 'quot':
        return '"';
      case 'apos':
        return "'";
      case 'hellip':
        return '…';
      case 'mdash':
        return '—';
      case 'ndash':
        return '–';
    }
    return m.group(0)!;
  });
}

class _Acc {
  StringBuffer text = StringBuffer();
  StringBuffer html = StringBuffer();
  int attachments = 0;
}

void _walk(Map<String, String> headers, String body, _Acc acc) {
  final String rawType = headers['content-type'] ?? 'text/plain';
  final String type = rawType.toLowerCase();
  final String disposition = (headers['content-disposition'] ?? '').toLowerCase();
  final String transfer = (headers['content-transfer-encoding'] ?? '').trim().toLowerCase();
  final String charset = _param(rawType, 'charset');

  if (type.startsWith('multipart/')) {
    final String boundary = _param(rawType, 'boundary');
    if (boundary.isEmpty) return;
    for (final String part in _splitParts(body, boundary)) {
      final int split = part.indexOf('\n\n');
      final Map<String, String> sub = parseHeaders(split < 0 ? part : part.substring(0, split));
      final String rest = split < 0 ? '' : part.substring(split + 2);
      _walk(sub, rest, acc);
    }
    return;
  }

  if (disposition.contains('attachment')) {
    acc.attachments += 1;
    return;
  }

  final bool isPlain = type.startsWith('text/plain') || type.isEmpty;
  final bool isHtml = type.startsWith('text/html');
  if (!isPlain && !isHtml) {
    acc.attachments += 1;
    return;
  }
  // 纯文本那份已经拿到了就不覆盖：多段的中英双语正文取第一段。
  if (isPlain && acc.text.isNotEmpty) return;
  if (isHtml && acc.html.isNotEmpty) return;

  final String decoded = switch (transfer) {
    'base64' => _decodeBase64(body, charset),
    'quoted-printable' => _decodeQuoted(body, charset),
    _ => decodeBytesText(body, charset),
  };
  if (isPlain) {
    acc.text.write(decoded);
  } else {
    acc.html.write(decoded);
  }
}

/// 按 boundary 切开 multipart 正文。第一条界线前面那段是解说，最后一条带 `--` 是收尾。
List<String> _splitParts(String body, String boundary) {
  final List<String> out = <String>[];
  final List<String> chunks = body.split('--$boundary');
  for (int i = 1; i < chunks.length; i += 1) {
    final String part = chunks[i];
    if (part.startsWith('--')) break; // --boundary-- 收尾
    out.add(_trimPart(part));
  }
  return out.where((String s) => s.trim().isNotEmpty).toList();
}

String _trimPart(String chunk) {
  String s = chunk;
  while (s.startsWith('\n')) {
    s = s.substring(1);
  }
  while (s.endsWith('\n')) {
    s = s.substring(0, s.length - 1);
  }
  return s;
}

/// `Content-Type: multipart/mixed; boundary="xxx"` 里取某个参数。
String _param(String header, String name) {
  if (header.isEmpty) return '';
  final Match? m =
      RegExp('$name\\s*=\\s*"([^"]*)"', caseSensitive: false).firstMatch(header) ??
          RegExp('$name\\s*=\\s*([^;\\s]+)', caseSensitive: false).firstMatch(header);
  return m == null ? '' : (m.group(1) ?? '').trim();
}

String _decodeBase64(String body, String charset) {
  final String cleaned = body.replaceAll(RegExp(r'\s'), '');
  if (cleaned.isEmpty) return '';
  final String padded = cleaned.padRight((cleaned.length + 3) ~/ 4 * 4, '=');
  try {
    return decodeBytesText(latin1.decode(base64.decode(padded), allowInvalid: true), charset);
  } catch (_) {
    return '';
  }
}

String _decodeQuoted(String body, String charset) {
  if (!body.contains('=')) return decodeBytesText(body, charset);
  final List<int> out = <int>[];
  int i = 0;
  while (i < body.length) {
    final String c = body[i];
    if (c != '=') {
      out.addAll(_bytesOf(c));
      i += 1;
      continue;
    }
    // 软换行：= 后面紧跟换行，什么也不输出。
    if (i + 1 < body.length && (body[i + 1] == '\n' || body[i + 1] == '\r')) {
      i += 1;
      if (i < body.length && body[i] == '\r') i += 1;
      if (i < body.length && body[i] == '\n') i += 1;
      continue;
    }
    if (i + 2 < body.length) {
      final int? code = int.tryParse(body.substring(i + 1, i + 3), radix: 16);
      if (code != null) {
        out.add(code);
        i += 3;
        continue;
      }
    }
    out.add(0x3d);
    i += 1;
  }
  return decodeBytesText(latin1.decode(out, allowInvalid: true), charset);
}

/// `=?…?Q?…?=` 里那种写法：`=XX` 是字节，`_` 是空格。
String _percentToQuestion(String text) =>
    text.replaceAll('_', '=20');

/// 一个「字符」背后其实是几个字节。读 socket 时按 latin1 落的，这里原样还原。
List<int> _bytesOf(String text) {
  if (text.isEmpty) return const <int>[];
  final List<int> out = <int>[];
  for (final int c in text.codeUnits) {
    // 真拿到 255 以上的字符说明它已经不是字节了，宁可写个问号也别为了一个怪字符炸掉整封信。
    out.add(c <= 255 ? c : 0x3f);
  }
  return out;
}

/// 头部里夹着原始 8 位字节（没走 `=?…?=`）的那种，按 UTF-8 或 GBK 重新认一遍。
String repairByteText(String text) {
  if (text.isEmpty) return text;
  bool high = false;
  for (final int c in text.codeUnits) {
    if (c > 255) return text; // 已经是正常文本
    if (c >= 128) high = true;
  }
  if (!high) return text;
  final List<int> bytes = _bytesOf(text);
  final String? strict = _utf8OrNull(bytes);
  if (strict != null) return strict;
  final String gbk = decodeGbk(bytes);
  if (!gbk.contains('\uFFFD')) return gbk;
  return text;
}
