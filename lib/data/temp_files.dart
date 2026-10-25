import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 临时文件区里的一条。`path` 是相对路径，像 `reports/a.md`。
class TempFile {
  const TempFile({
    required this.path,
    required this.size,
    required this.modified,
  });

  final String path;
  final int size;
  final DateTime modified;

  String get name => path.split('/').last;

  String get ext {
    final int dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool get isImage =>
      const <String>{'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'}.contains(ext);

  /// 认得出来的文本类型。读的时候还会再看一眼有没有 0 字节，二进制一律当读不了。
  bool get isText => const <String>{
        'txt', 'md', 'markdown', 'json', 'csv', 'tsv', 'log', 'yaml', 'yml',
        'conf', 'cfg', 'ini', 'env', 'sh', 'bash', 'zsh', 'dart', 'py', 'js',
        'ts', 'html', 'css', 'xml', 'sql', 'toml', 'service', 'pem', 'pub',
      }.contains(ext);
}

/// 模型和用户共用的那块临时空间。就是 agent 的工作目录，`file_io` 写进来的
/// 东西也在这里。读写都锁在这个目录里面，跑出去的一律不认。
class TempFiles {
  TempFiles(this.root);

  final Directory root;

  /// 单个文件的上限，传服务器时也会照这个拦。
  static const int maxBytes = 8 * 1024 * 1024;

  /// 一次读出来的字符上限。
  static const int readChars = 200000;

  void ensure() {
    if (!root.existsSync()) root.createSync(recursive: true);
  }

  /// 只留文件名本身，别的字符换成下划线。CJK 保留。
  static String cleanName(String raw) {
    final String base = raw.replaceAll('\\', '/').split('/').last.trim();
    final StringBuffer out = StringBuffer();
    for (final int c in base.runes) {
      final String ch = String.fromCharCode(c);
      final bool plain = (c >= 48 && c <= 57) ||
          (c >= 65 && c <= 90) ||
          (c >= 97 && c <= 122) ||
          ch == '.' ||
          ch == '-' ||
          ch == '_' ||
          c > 0x7f;
      out.write(plain ? ch : '_');
    }
    String name = out.toString();
    while (name.startsWith('.')) {
      name = name.substring(1);
    }
    if (name.isEmpty) name = 'file';
    if (name.length > 80) {
      final int dot = name.lastIndexOf('.');
      final String tail = dot > 0 && name.length - dot <= 12 ? name.substring(dot) : '';
      name = '${name.substring(0, 80 - tail.length)}$tail';
    }
    return name;
  }

  /// 相对路径逐段洗干净，空段和 `..` 直接丢掉。
  static String cleanPath(String raw) {
    final List<String> parts = <String>[];
    for (final String seg in raw.replaceAll('\\', '/').split('/')) {
      final String text = seg.trim();
      if (text.isEmpty || text == '.') continue;
      parts.add(cleanName(text));
    }
    return parts.join('/');
  }

  /// 相对路径 → 文件。绝对路径和带 `..` 的都给 null。
  File? fileOf(String rel) {
    final String text = rel.replaceAll('\\', '/').trim();
    if (text.isEmpty || text.startsWith('/')) return null;
    final List<String> parts = <String>[];
    for (final String seg in text.split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') return null;
      parts.add(seg);
    }
    if (parts.isEmpty) return null;
    return File('${root.path}/${parts.join('/')}');
  }

  List<TempFile> list() {
    ensure();
    final List<TempFile> out = <TempFile>[];
    for (final FileSystemEntity e
        in root.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final String rel = e.path.substring(root.path.length + 1).replaceAll('\\', '/');
      final FileStat st = e.statSync();
      out.add(TempFile(path: rel, size: st.size, modified: st.modified));
    }
    out.sort((TempFile a, TempFile b) => b.modified.compareTo(a.modified));
    return out;
  }

  int totalBytes() {
    int sum = 0;
    for (final TempFile f in list()) {
      sum += f.size;
    }
    return sum;
  }

  TempFile _describe(File f) {
    final FileStat st = f.statSync();
    final String rel = f.path.substring(root.path.length + 1).replaceAll('\\', '/');
    return TempFile(path: rel, size: st.size, modified: st.modified);
  }

  /// 同名就加 `-2`、`-3`，不覆盖上一份。
  File _fresh(String name) {
    File f = File('${root.path}/$name');
    if (!f.existsSync()) return f;
    final int dot = name.lastIndexOf('.');
    final String stem = dot > 0 ? name.substring(0, dot) : name;
    final String tail = dot > 0 ? name.substring(dot) : '';
    for (int i = 2; i < 1000; i += 1) {
      f = File('${root.path}/$stem-$i$tail');
      if (!f.existsSync()) return f;
    }
    return f;
  }

  Future<TempFile> save(String name, List<int> bytes) async {
    ensure();
    if (bytes.length > maxBytes) {
      throw StateError('超过 ${maxBytes ~/ (1024 * 1024)} MB，临时文件区不收。');
    }
    final File f = _fresh(cleanName(name));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    return _describe(f);
  }

  Future<TempFile> saveText(String path, String text) async {
    ensure();
    final String cleaned = cleanPath(path);
    if (cleaned.isEmpty) throw StateError('路径是空的。');
    final Uint8List bytes = Uint8List.fromList(utf8.encode(text));
    if (bytes.length > maxBytes) {
      throw StateError('超过 ${maxBytes ~/ (1024 * 1024)} MB，临时文件区不收。');
    }
    final File f = File('${root.path}/$cleaned');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
    return _describe(f);
  }

  /// 读文本。不存在、读不了、看着是二进制，都返回 null。
  Future<String?> readText(String rel, {int limit = readChars}) async {
    final File? f = fileOf(rel);
    if (f == null || !f.existsSync()) return null;
    RandomAccessFile? raf;
    try {
      raf = await f.open();
      final int size = await raf.length();
      final int want = size > limit * 4 ? limit * 4 : size;
      final Uint8List bytes = await raf.read(want);
      final int head = bytes.length > 8192 ? 8192 : bytes.length;
      for (int i = 0; i < head; i += 1) {
        if (bytes[i] == 0) return null;
      }
      final String text = utf8.decode(bytes, allowMalformed: true);
      return text.length > limit ? text.substring(0, limit) : text;
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  Future<bool> remove(String rel) async {
    final File? f = fileOf(rel);
    if (f == null || !f.existsSync()) return false;
    await f.delete();
    return true;
  }

  Future<void> clear() async {
    ensure();
    for (final FileSystemEntity e in root.listSync(followLinks: false)) {
      try {
        await e.delete(recursive: true);
      } catch (_) {
        // 删不掉的那个就留着。
      }
    }
  }
}

/// `1.2 MB` 这种。列表和提示都按这个写。
String tempSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
