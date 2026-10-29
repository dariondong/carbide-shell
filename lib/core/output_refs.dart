/// 一段话里提到的、能在对话里直接看一眼的文件。
///
/// 只认两种：图片和网页。别的一律交给临时文件页，免得每句话后面都挂一排卡片。
library;

/// 认得出来的那几种后缀。
const Set<String> kPreviewExt = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'html',
  'htm',
};

/// 字里写到的路径。`http://`、`data:` 这种外链不算。
///
/// 这里只负责切出候选，文件到底在不在由调用方去问磁盘。
List<String> outputRefs(String text) {
  if (text.isEmpty || !text.contains('.')) return const <String>[];
  final RegExp re = RegExp(
    r'[^\s`"（），。；、()\[\]<>|,;:]+\.(?:png|jpe?g|gif|webp|bmp|html?)',
    caseSensitive: false,
  );
  final List<String> out = <String>[];
  for (final RegExpMatch m in re.allMatches(text)) {
    String path = m.group(0) ?? '';
    if (path.isEmpty) continue;
    if (path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:') ||
        path.startsWith('file:')) {
      continue;
    }
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    final String ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
    if (!kPreviewExt.contains(ext)) continue;
    if (!out.contains(path)) out.add(path);
  }
  return out;
}

/// 后缀决定这一条是图还是网页。
bool isImageRef(String path) {
  final String ext = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
  return ext != 'html' && ext != 'htm';
}
