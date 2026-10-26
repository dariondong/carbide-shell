/// 模型输出的那点 Markdown：拆成块与行内片段，界面照着画。
///
/// 只认模型真会写的那几样：标题、围栏代码、列表、引用、分隔线、表格，
/// 行内认粗体、斜体、行内代码、删除线与链接。没写完的标记当普通字，
/// 正在逐字输出的时候不会一会儿有星号一会儿没有。
library;

/// 一块东西。
enum MdBlockKind { paragraph, heading, code, bullet, ordered, quote, rule, table }

class MdBlock {
  const MdBlock(
    this.kind, {
    this.text = '',
    this.level = 1,
    this.lang = '',
    this.number = 1,
    this.rows = const <List<String>>[],
  });

  final MdBlockKind kind;

  /// 段落 / 标题 / 引用 / 列表项 / 代码正文。
  final String text;

  /// 标题级数（1..6）或者列表缩进层数（1..）。
  final int level;

  /// 围栏后面那个语言名，没有就是空串。
  final String lang;

  /// 有序列表的那个号码，用的是原文写的数。
  final int number;

  /// 表格的行，第一行是表头。
  final List<List<String>> rows;
}

/// 行内的一小段。
enum MdSpanKind { plain, bold, italic, code, strike, link }

class MdSpan {
  const MdSpan(this.text, {this.kind = MdSpanKind.plain, this.href = ''});

  final String text;
  final MdSpanKind kind;

  /// 链接地址，只有 kind 是 link 时有。
  final String href;
}

final RegExp _rule = RegExp(r'^([-*_])(\s*\1){2,}$');
final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _bullet = RegExp(r'^(\s*)([-*+])\s+(.*)$');
final RegExp _ordered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
final RegExp _fence = RegExp(r'^(```+|~~~+)\s*([^\s`]*)');
final RegExp _tableRule = RegExp(r'^\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?$');

/// 整段文字拆成块。
List<MdBlock> parseMarkdown(String source) {
  final List<String> lines = source.replaceAll('\r\n', '\n').split('\n');
  final List<MdBlock> out = <MdBlock>[];
  int i = 0;
  while (i < lines.length) {
    final String line = lines[i];
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      i += 1;
      continue;
    }

    final RegExpMatch? fence = _fence.firstMatch(trimmed);
    if (fence != null) {
      final String mark = fence.group(1)!.substring(0, 3);
      final List<String> body = <String>[];
      i += 1;
      while (i < lines.length && !lines[i].trim().startsWith(mark)) {
        body.add(lines[i]);
        i += 1;
      }
      if (i < lines.length) i += 1; // 收尾那行
      out.add(MdBlock(MdBlockKind.code,
          text: body.join('\n'), lang: (fence.group(2) ?? '').toLowerCase()));
      continue;
    }
    if (_rule.hasMatch(trimmed)) {
      out.add(const MdBlock(MdBlockKind.rule));
      i += 1;
      continue;
    }
    final RegExpMatch? head = _heading.firstMatch(trimmed);
    if (head != null) {
      out.add(MdBlock(MdBlockKind.heading,
          text: head.group(2)!.trim(), level: head.group(1)!.length));
      i += 1;
      continue;
    }
    if (_isTable(lines, i)) {
      final List<List<String>> rows = <List<String>>[_cells(lines[i])];
      i += 2; // 表头 + 那条分隔线
      while (i < lines.length && lines[i].trim().contains('|') && lines[i].trim().isNotEmpty) {
        rows.add(_cells(lines[i]));
        i += 1;
      }
      out.add(MdBlock(MdBlockKind.table, rows: rows));
      continue;
    }
    if (trimmed.startsWith('>')) {
      final List<String> body = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        body.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i += 1;
      }
      out.add(MdBlock(MdBlockKind.quote, text: body.join('\n')));
      continue;
    }
    final RegExpMatch? bullet = _bullet.firstMatch(line);
    final RegExpMatch? ordered = bullet == null ? _ordered.firstMatch(line) : null;
    if (bullet != null || ordered != null) {
      final RegExpMatch hit = bullet ?? ordered!;
      final int depth = hit.group(1)!.length ~/ 2 + 1;
      final List<String> body = <String>[hit.group(3)!.trim()];
      i += 1;
      // 缩进接着写的几行算同一项
      while (i < lines.length &&
          lines[i].startsWith('  ') &&
          lines[i].trim().isNotEmpty &&
          !_bullet.hasMatch(lines[i]) &&
          !_ordered.hasMatch(lines[i])) {
        body.add(lines[i].trim());
        i += 1;
      }
      if (bullet != null) {
        out.add(MdBlock(MdBlockKind.bullet, text: body.join('\n'), level: depth));
      } else {
        out.add(MdBlock(MdBlockKind.ordered,
            text: body.join('\n'),
            level: depth,
            number: int.tryParse(hit.group(2)!) ?? 1));
      }
      continue;
    }

    // 上面前几样都不是，就当普通段落，直到空行或者另起一块
    final List<String> para = <String>[];
    while (i < lines.length) {
      final String t = lines[i].trim();
      if (t.isEmpty) break;
      if (_fence.hasMatch(t) ||
          _rule.hasMatch(t) ||
          _heading.hasMatch(t) ||
          _bullet.hasMatch(lines[i]) ||
          _ordered.hasMatch(lines[i]) ||
          t.startsWith('>') ||
          _isTable(lines, i)) {
        break;
      }
      para.add(t);
      i += 1;
    }
    if (para.isEmpty) {
      i += 1; // 没接住的行（极少），别在这儿转圈
      continue;
    }
    out.add(MdBlock(MdBlockKind.paragraph, text: para.join('\n')));
  }
  return out;
}

bool _isTable(List<String> lines, int at) {
  if (at + 1 >= lines.length) return false;
  if (!lines[at].contains('|')) return false;
  if (!lines[at + 1].contains('|')) return false;
  return _tableRule.hasMatch(lines[at + 1].trim());
}

List<String> _cells(String line) {
  String s = line.trim();
  if (s.startsWith('|')) s = s.substring(1);
  if (s.endsWith('|')) s = s.substring(0, s.length - 1);
  return s.split('|').map((String c) => c.trim()).toList();
}

/// 一行里的粗体、斜体、行内代码、删除线、链接。彼此不嵌套，套着的按普通字放回去。
List<MdSpan> parseInline(String source) {
  final List<MdSpan> out = <MdSpan>[];
  final StringBuffer plain = StringBuffer();

  void flush() {
    if (plain.isEmpty) return;
    out.add(MdSpan(plain.toString()));
    plain.clear();
  }

  bool wordBefore(int at) {
    if (at <= 0) return false;
    final String ch = source[at - 1];
    return RegExp(r'[0-9A-Za-z]').hasMatch(ch);
  }

  bool wordAfter(int at) {
    if (at >= source.length) return false;
    return RegExp(r'[0-9A-Za-z]').hasMatch(source[at]);
  }

  int i = 0;
  while (i < source.length) {
    final String rest = source.substring(i);
    if (rest.startsWith('`')) {
      final int end = source.indexOf('`', i + 1);
      if (end > i + 1) {
        flush();
        out.add(MdSpan(source.substring(i + 1, end), kind: MdSpanKind.code));
        i = end + 1;
        continue;
      }
    }
    if (rest.startsWith('**') || rest.startsWith('__')) {
      final String mark = rest.substring(0, 2);
      final int end = source.indexOf(mark, i + 2);
      if (end > i + 2) {
        flush();
        out.add(MdSpan(source.substring(i + 2, end), kind: MdSpanKind.bold));
        i = end + 2;
        continue;
      }
    }
    if (rest.startsWith('~~')) {
      final int end = source.indexOf('~~', i + 2);
      if (end > i + 2) {
        flush();
        out.add(MdSpan(source.substring(i + 2, end), kind: MdSpanKind.strike));
        i = end + 2;
        continue;
      }
    }
    if (rest.startsWith('[')) {
      final int close = source.indexOf('](', i + 1);
      if (close > i + 1) {
        final int end = source.indexOf(')', close + 2);
        if (end > close + 2) {
          flush();
          out.add(MdSpan(source.substring(i + 1, close),
              kind: MdSpanKind.link, href: source.substring(close + 2, end)));
          i = end + 1;
          continue;
        }
      }
    }
    // 裸地址也认：回话里直接甩出来的 https://… 点一下就能打开。
    if (source.startsWith('https://', i) ||
        source.startsWith('http://', i) ||
        (rest.startsWith('www.') && !wordBefore(i))) {
      final int end = _bareUrlEnd(source, i);
      final String url = source.substring(i, end);
      if (_looksLikeUrl(url)) {
        flush();
        out.add(MdSpan(url,
            kind: MdSpanKind.link,
            href: url.startsWith('www.') ? 'https://$url' : url));
        i = end;
        continue;
      }
    }
    if (rest.startsWith('*') || (rest.startsWith('_') && !wordBefore(i))) {
      final String mark = source[i];
      int end = source.indexOf(mark, i + 1);
      // 下划线夹在词里（foo_bar）不算斜体
      if (mark == '_' && end > 0 && wordAfter(end + 1)) end = -1;
      if (end > i + 1) {
        flush();
        out.add(MdSpan(source.substring(i + 1, end), kind: MdSpanKind.italic));
        i = end + 1;
        continue;
      }
    }
    plain.write(source[i]);
    i += 1;
  }
  flush();
  return out;
}

/// 只认地址的一段：等宽输出这类不画 Markdown 的地方用它。
List<MdSpan> linkifyPlain(String source) {
  final List<MdSpan> out = <MdSpan>[];
  int plainFrom = 0;
  int i = 0;
  while (i < source.length) {
    final bool head = source.startsWith('https://', i) ||
        source.startsWith('http://', i) ||
        (source.startsWith('www.', i) && !_wordBefore(source, i));
    if (!head) {
      i += 1;
      continue;
    }
    final int end = _bareUrlEnd(source, i);
    final String url = source.substring(i, end);
    if (!_looksLikeUrl(url)) {
      i += 1;
      continue;
    }
    if (i > plainFrom) out.add(MdSpan(source.substring(plainFrom, i)));
    out.add(MdSpan(url,
        kind: MdSpanKind.link, href: url.startsWith('www.') ? 'https://$url' : url));
    plainFrom = end;
    i = end;
  }
  if (plainFrom < source.length) out.add(MdSpan(source.substring(plainFrom)));
  return out;
}

/// 光秃秃的 http:// 不算；www 开头的短一点也算数。
bool _looksLikeUrl(String url) {
  if (url.startsWith('www.')) return url.length >= 5;
  return url.length >= 10;
}

bool _wordBefore(String s, int at) {
  if (at <= 0) return false;
  return RegExp(r'[0-9A-Za-z]').hasMatch(s[at - 1]);
}

/// 裸地址到哪儿为止：空白、中文标点、收尾的括号引号都算断处；
/// 句末那几个 . , ; : ! ? 一并去掉，地址里的 / ? = & # 留着。
int _bareUrlEnd(String s, int start) {
  const String stop = ' \t\r\n<>"`，。；：！？、）】》”’';
  int i = start;
  while (i < s.length) {
    final String ch = s[i];
    if (stop.contains(ch) || ch == ')' || ch == ']' || ch == '}') break;
    i += 1;
  }
  while (i > start) {
    final String ch = s[i - 1];
    if (ch == '.' || ch == ',' || ch == ';' || ch == ':' || ch == '!' || ch == '?') {
      i -= 1;
    } else {
      break;
    }
  }
  return i;
}
