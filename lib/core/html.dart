/// 把一份 HTML 收成 Markdown 再画出来。
///
/// 临时文件区里躺着的 `.html` 大多是模型写的小报告，用不着装一个浏览器内核：
/// 标题、段落、列表、引用、代码、表格、粗细斜、链接这些认得出来的先收成
/// Markdown，交给 [MdText] 按同一套字排出来。认不出的标签直接丢掉，文字留下。
///
/// 这不是一个通用的 HTML 渲染器：不认样式表、不认脚本、不认布局。要看原样就
/// 切到「原文」，或者下载下来用浏览器看。
library;

/// 丢掉整块内容的标签：里面的字不给人看。
const Set<String> _dropped = <String>{
  'script',
  'style',
  'head',
  'noscript',
  'svg',
  'template',
  'iframe',
};

/// 一碰到就断一行、再空一行的块级标签。
const Set<String> _block = <String>{
  'p',
  'div',
  'section',
  'article',
  'header',
  'footer',
  'main',
  'nav',
  'aside',
  'figure',
  'figcaption',
  'form',
  'dl',
  'dt',
  'dd',
  'address',
  'center',
  'body',
  'html',
  'tbody',
  'thead',
  'tfoot',
};

/// 断一行、不多空一行的标签。
const Set<String> _line = <String>{'tr', 'br', 'hr', 'caption', 'option', 'legend'};

/// HTML → Markdown。空输入给空串。
String htmlToMarkdown(String html) {
  final StringBuffer out = StringBuffer();
  final List<String> inline = <String>[];
  final List<_ListState> lists = <_ListState>[];
  bool inPre = false;
  bool inDrop = false;
  String dropTag = '';
  String? linkHref;
  int tableRow = 0;

  void text(String raw) {
    if (raw.isEmpty || inDrop) return;
    if (inPre) {
      out.write(_decode(raw));
      return;
    }
    final String flat = _decode(raw).replaceAll(RegExp(r'[\s\u00a0]+'), ' ');
    if (flat.trim().isEmpty) {
      // 标签之间那点空白只在句子中间有用，行首行尾不要占位。
      if (out.isNotEmpty && !out.toString().endsWith(' ') && !out.toString().endsWith('\n')) {
        out.write(' ');
      }
      return;
    }
    out.write(flat);
  }

  void newline([int count = 1]) {
    final String now = out.toString();
    int have = 0;
    for (int i = now.length - 1; i >= 0 && now[i] == '\n'; i -= 1) {
      have += 1;
    }
    if (have >= count) return;
    out.write('\n' * (count - have));
  }

  void closeInline(String tag) {
    if (inline.isEmpty) return;
    // 只收掉自己那一层：交错的标签不去猜结构。
    final int at = inline.lastIndexOf(_closeOf(tag));
    if (at < 0) return;
    out.write(inline.removeAt(at));
  }

  int i = 0;
  while (i < html.length) {
    final int lt = html.indexOf('<', i);
    if (lt < 0) {
      text(html.substring(i));
      break;
    }
    if (lt > i) text(html.substring(i, lt));
    if (html.startsWith('<!--', lt)) {
      final int end = html.indexOf('-->', lt);
      i = end < 0 ? html.length : end + 3;
      continue;
    }
    if (html.startsWith('<!', lt) || html.startsWith('<?', lt)) {
      final int end = html.indexOf('>', lt);
      i = end < 0 ? html.length : end + 1;
      continue;
    }
    final int gt = html.indexOf('>', lt);
    if (gt < 0) {
      text(html.substring(lt));
      break;
    }
    final String body = html.substring(lt + 1, gt);
    i = gt + 1;
    final bool closing = body.startsWith('/');
    final String name = _tagName(body);
    if (name.isEmpty) continue;
    if (inDrop) {
      if (closing && name == dropTag) inDrop = false;
      continue;
    }
    if (!closing && _dropped.contains(name)) {
      inDrop = true;
      dropTag = name;
      continue;
    }
    if (name == 'pre') {
      if (closing) {
        newline();
        out.write('```');
        newline(2);
        inPre = false;
      } else {
        newline(2);
        out.write('```');
        newline();
        inPre = true;
      }
      continue;
    }
    if (inPre) continue;
    switch (name) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        if (closing) {
          newline(2);
        } else {
          newline(2);
          final int level = int.parse(name.substring(1));
          out.write('${'#' * level} ');
        }
        break;
      case 'blockquote':
        if (closing) {
          newline(2);
        } else {
          newline(2);
          out.write('> ');
        }
        break;
      case 'ul':
      case 'ol':
        if (closing) {
          if (lists.isNotEmpty) lists.removeLast();
          newline();
        } else {
          newline(lists.isEmpty ? 2 : 1);
          lists.add(_ListState(ordered: name == 'ol'));
        }
        break;
      case 'li':
        if (closing) {
          newline();
        } else {
          newline();
          final int depth = lists.isEmpty ? 0 : lists.length - 1;
          final String pad = '  ' * depth;
          if (lists.isNotEmpty && lists.last.ordered) {
            lists.last.count += 1;
            out.write('$pad${lists.last.count}. ');
          } else {
            out.write('$pad- ');
          }
        }
        break;
      case 'tr':
        if (closing) {
          out.write('|');
          tableRow += 1;
          if (tableRow == 1) {
            // 表头下面那条分隔线，MdText 靠它认表。
            newline();
            out.write('| --- |');
          }
          newline();
        } else {
          newline();
        }
        break;
      case 'td':
      case 'th':
        if (closing) {
          out.write(' ');
        } else {
          out.write('| ');
        }
        break;
      case 'table':
        if (closing) {
          tableRow = 0;
          newline(2);
        } else {
          newline(2);
        }
        break;
      case 'hr':
        newline(2);
        out.write('---');
        newline(2);
        break;
      case 'strong':
      case 'b':
        if (closing) {
          closeInline(name);
        } else {
          inline.add('**');
          out.write('**');
        }
        break;
      case 'em':
      case 'i':
        if (closing) {
          closeInline(name);
        } else {
          inline.add('*');
          out.write('*');
        }
        break;
      case 'del':
      case 's':
      case 'strike':
        if (closing) {
          closeInline(name);
        } else {
          inline.add('~~');
          out.write('~~');
        }
        break;
      case 'code':
        if (closing) {
          closeInline(name);
        } else {
          inline.add('`');
          out.write('`');
        }
        break;
      case 'a':
        if (closing) {
          final String? href = linkHref;
          out.write(href == null ? ']' : ']($href)');
          linkHref = null;
        } else {
          linkHref = _attr(body, 'href');
          out.write('[');
        }
        break;
      case 'img':
        final String? alt = _attr(body, 'alt');
        final String? src = _attr(body, 'src');
        if (alt != null && alt.isNotEmpty) {
          out.write('[$alt]');
        } else if (src != null && src.isNotEmpty) {
          out.write('[图片]');
        }
        break;
      default:
        if (_block.contains(name) || _line.contains(name)) newline(name == 'br' ? 1 : 1);
        break;
    }
  }

  while (inline.isNotEmpty) {
    out.write(inline.removeLast());
  }
  return _tidy(out.toString());
}

class _ListState {
  _ListState({required this.ordered});

  final bool ordered;
  int count = 0;
}

String _closeOf(String tag) {
  switch (tag) {
    case 'strong':
    case 'b':
      return '**';
    case 'del':
    case 's':
    case 'strike':
      return '~~';
    case 'em':
    case 'i':
      return '*';
    default:
      return '`';
  }
}

/// `<div class=…>` → `div`，`</div>` 也是 `div`。
String _tagName(String body) {
  final String flat = body.startsWith('/') ? body.substring(1) : body;
  final int end = flat.indexOf(RegExp(r'[\s/>]'));
  final String raw = end < 0 ? flat : flat.substring(0, end);
  return raw.replaceAll('/', '').toLowerCase();
}

/// 取一个属性值，单双引号都认。
String? _attr(String body, String key) {
  final RegExp re = RegExp('$key\\s*=\\s*("([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false);
  final RegExpMatch? m = re.firstMatch(body);
  if (m == null) return null;
  return _decode(m.group(2) ?? m.group(3) ?? m.group(4) ?? '');
}

const Map<String, String> _entities = <String, String>{
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
  'mdash': '—',
  'ndash': '–',
  'hellip': '…',
  'middot': '·',
  'copy': '©',
  'reg': '®',
  'trade': '™',
  'times': '×',
  'divide': '÷',
  'laquo': '«',
  'raquo': '»',
  'ldquo': '“',
  'rdquo': '”',
  'lsquo': '‘',
  'rsquo': '’',
  'emsp': ' ',
  'ensp': ' ',
  'thinsp': ' ',
  'deg': '°',
  'plusmn': '±',
  'micro': 'µ',
  'para': '¶',
  'sect': '§',
  'yen': '¥',
  'euro': '€',
  'larr': '←',
  'rarr': '→',
  'uarr': '↑',
  'darr': '↓',
};

final RegExp _entity = RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);');

String _decode(String raw) {
  if (!raw.contains('&')) return raw;
  return raw.replaceAllMapped(_entity, (Match m) {
    final String body = m.group(1)!;
    if (body.startsWith('#')) {
      final bool hex = body.length > 1 && (body[1] == 'x' || body[1] == 'X');
      final int? code =
          int.tryParse(hex ? body.substring(2) : body.substring(1), radix: hex ? 16 : 10);
      if (code == null || code < 0 || code > 0x10ffff) return m.group(0)!;
      return String.fromCharCode(code);
    }
    return _entities[body.toLowerCase()] ?? m.group(0)!;
  });
}

/// 收尾：行首空格、行尾空白、连着的空行都抹平；代码块里一行不动。
String _tidy(String raw) {
  final List<String> lines = <String>[];
  final List<bool> frozen = <bool>[];
  bool inFence = false;
  for (final String line in raw.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      lines.add(line.trim());
      frozen.add(true);
      continue;
    }
    if (inFence) {
      lines.add(line.trimRight());
      frozen.add(true);
      continue;
    }
    String trimmed = line.trimRight();
    // 行首那个空格是标签之间留下的，抹掉；列表、引用、表格的缩进不能抹。
    final String rest = trimmed.trimLeft();
    final bool keepsIndent = rest.startsWith('-') ||
        rest.startsWith('>') ||
        rest.startsWith('|') ||
        RegExp(r'^\d+\. ').hasMatch(rest);
    if (!keepsIndent) trimmed = rest;
    final bool blank = trimmed.trim().isEmpty;
    if (blank && (lines.isEmpty || (lines.last.trim().isEmpty && !frozen.last))) {
      continue;
    }
    lines.add(blank ? '' : trimmed);
    frozen.add(false);
  }
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  final String joined = lines.join('\n');
  return joined.trim();
}
