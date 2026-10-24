import 'dart:convert';
import 'dart:io' show ZLibDecoder;

/// Word（.docx）里的正文，读成纯文字。
///
/// .docx 是个 zip，正文全是 `word/document.xml` 里的文字。这里只取文字：
/// 段落之间换行，制表符与软换行按原样，页码、图片、批注都不要。
/// 认不出来（不是 zip、压缩包里没有正文、压缩方式不认识）就返回 null，
/// 让调用方说「这个文件读不了」，不拿半截东西冒充。
String? docxText(List<int> bytes) {
  final ({List<int> data, int method})? part = _entry(bytes, 'word/document.xml');
  if (part == null) return null;
  final List<int> plain;
  try {
    plain = part.method == 0
        ? part.data
        : ZLibDecoder(raw: true).convert(part.data);
  } catch (_) {
    return null;
  }
  final String xml = utf8.decode(plain, allowMalformed: true);
  final String text = _xmlToText(xml);
  return text.isEmpty ? null : text;
}

/// 从 zip 中央目录里找一条：拿到还没解压的字节与压缩方式（0 存、8 deflate）。
///
/// 走中央目录而不是顺着本地头扫：写了数据描述符的条目，本地头里的长度是 0。
({List<int> data, int method})? _entry(List<int> bytes, String name) {
  final int end = _findEnd(bytes);
  if (end < 0) return null;
  final int count = _u16(bytes, end + 10);
  final int start = _u32(bytes, end + 16);
  if (count == 0xFFFF || start == 0xFFFFFFFF) return null; // zip64：这个包不该这么大
  if (start <= 0 || start + 46 > bytes.length) return null;
  int at = start;
  for (int i = 0; i < count; i += 1) {
    if (!_at(bytes, at, <int>[0x50, 0x4B, 0x01, 0x02])) return null;
    final int method = _u16(bytes, at + 10);
    final int packed = _u32(bytes, at + 20);
    final int nameLen = _u16(bytes, at + 28);
    final int extraLen = _u16(bytes, at + 30);
    final int commentLen = _u16(bytes, at + 32);
    final int local = _u32(bytes, at + 42);
    final String entry = utf8.decode(
      bytes.sublist(at + 46, at + 46 + nameLen),
      allowMalformed: true,
    );
    if (entry == name) return _slice(bytes, local, packed, method);
    at += 46 + nameLen + extraLen + commentLen;
  }
  return null;
}

/// 本地头后面就是数据；名字和扩展字段的长度只认本地头里那份。
({List<int> data, int method})? _slice(List<int> bytes, int local, int packed, int method) {
  if (local < 0 || local + 30 > bytes.length) return null;
  if (!_at(bytes, local, <int>[0x50, 0x4B, 0x03, 0x04])) return null;
  final int data = local + 30 + _u16(bytes, local + 26) + _u16(bytes, local + 28);
  if (data < 0 || packed < 0 || data + packed > bytes.length) return null;
  return (data: bytes.sublist(data, data + packed), method: method);
}

/// zip 结尾那张目录表的位置，从尾巴往前找。
int _findEnd(List<int> bytes) {
  final int floor = bytes.length - 66000 < 0 ? 0 : bytes.length - 66000;
  for (int i = bytes.length - 22; i >= floor; i -= 1) {
    if (_at(bytes, i, <int>[0x50, 0x4B, 0x05, 0x06])) return i;
  }
  return -1;
}

bool _at(List<int> bytes, int at, List<int> want) {
  if (at < 0 || at + want.length > bytes.length) return false;
  for (int i = 0; i < want.length; i += 1) {
    if (bytes[at + i] != want[i]) return false;
  }
  return true;
}

int _u16(List<int> bytes, int at) {
  if (at < 0 || at + 2 > bytes.length) return 0;
  return bytes[at] | (bytes[at + 1] << 8);
}

int _u32(List<int> bytes, int at) {
  if (at < 0 || at + 4 > bytes.length) return 0;
  return bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24);
}

/// document.xml 到纯文字：段落结尾换行，制表符与软换行留着，别的标签一律去掉。
String _xmlToText(String xml) {
  String s = xml;
  // Word 存出来通常是一整行，也有编辑器会缩排。标签之间的换行是排版，不是正文。
  s = s.replaceAll(RegExp(r'>\n\s*<'), '><');
  // 域代码与修订痕迹里的旧文字不算正文
  s = s.replaceAll(RegExp(r'<w:instrText[^>]*>[\s\S]*?</w:instrText>'), '');
  s = s.replaceAll(RegExp(r'<w:delText[^>]*>[\s\S]*?</w:delText>'), '');
  s = s.replaceAll(RegExp(r'<w:tab\s*/>'), '\t');
  s = s.replaceAll(RegExp(r'<w:(br|cr)\s*/>'), '\n');
  s = s.replaceAll(RegExp(r'<w:p\s*/>'), '\n'); // 空段落也是一行
  s = s.replaceAll(RegExp(r'</w:p>'), '\n');
  s = s.replaceAll(RegExp(r'<[^>]*>'), '');
  s = _entities(s);
  s = s.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  s = s.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return s.trim();
}

/// 五个固定实体与数字实体。顺序要紧：&amp; 必须最后还原，否则 &amp;lt; 会被当成标签的尖括号。
String _entities(String text) {
  String s = text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
  s = s.replaceAllMapped(
    RegExp(r'&#(\d+);'),
    (Match m) => _char(int.tryParse(m.group(1)!)) ?? m.group(0)!,
  );
  s = s.replaceAllMapped(
    RegExp(r'&#[xX]([0-9a-fA-F]+);'),
    (Match m) => _char(int.tryParse(m.group(1)!, radix: 16)) ?? m.group(0)!,
  );
  return s.replaceAll('&amp;', '&');
}

/// 数字实体换回那个字；超出范围的当没认出来，原样留着。
String? _char(int? code) {
  if (code == null || code <= 0 || code > 0x10FFFF) return null;
  return String.fromCharCode(code);
}
