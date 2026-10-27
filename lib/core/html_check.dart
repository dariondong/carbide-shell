/// HTML 的静态体检：不渲染，只把「邮件客户端一定会剥掉或撑坏」的那几件事挑出来。
///
/// 手机上没有浏览器可开，所以这里不下「看起来怎么样」的结论，只报事实：
/// 有多少行内样式、有没有外链样式和图片、标签是否配平、有没有超过手机宽度的固定宽度。
library;

/// 一条发现。[level] 是 `warn` 或 `note`。
class HtmlIssue {
  const HtmlIssue(this.level, this.text);

  final String level;
  final String text;
}

class HtmlReport {
  const HtmlReport({
    required this.bytes,
    required this.elements,
    required this.inlineStyled,
    required this.issues,
  });

  final int bytes;

  /// 认出来的标签个数。
  final int elements;

  /// 带 `style="…"` 的标签个数。
  final int inlineStyled;

  final List<HtmlIssue> issues;

  bool get hasWarnings => issues.any((HtmlIssue i) => i.level == 'warn');

  /// 行内样式的覆盖率，0..1。
  double get inlineRate => elements == 0 ? 0 : inlineStyled / elements;
}

const Set<String> _voidTags = <String>{
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
  'param', 'source', 'track', 'wbr',
};

const Set<String> _skipBalance = <String>{'!doctype', 'html', 'head', 'body'};

/// 属性值外面的引号可有可无。
///
/// 写成 `['"]?` 塞进 raw 串会把字符串截断，所以单独拎出来用三引号 raw 串装着。
const String _q = r'''["']?''';

/// 体检一份 HTML。[email] 为真时按邮件客户端的脾气来判。
HtmlReport checkHtml(String html, {bool email = true}) {
  final List<HtmlIssue> issues = <HtmlIssue>[];
  final RegExp tag = RegExp(r'<\s*(/?)\s*([a-zA-Z][a-zA-Z0-9]*)');
  final Map<String, int> open = <String, int>{};
  int elements = 0;
  int styled = 0;

  for (final RegExpMatch match in tag.allMatches(html)) {
    final bool closing = match.group(1) == '/';
    final String name = (match.group(2) ?? '').toLowerCase();
    if (_skipBalance.contains(name)) continue;
    if (closing) {
      open[name] = (open[name] ?? 0) - 1;
      continue;
    }
    elements += 1;
    if (!_voidTags.contains(name)) open[name] = (open[name] ?? 0) + 1;
    // 只数标签本身那一段里有没有 style=，别被后面的正文带偏。
    final int end = html.indexOf('>', match.end);
    final String head = end < 0 ? '' : html.substring(match.end, end);
    if (RegExp(r'\sstyle\s*=').hasMatch(head)) styled += 1;
  }

  final List<String> unbalanced = <String>[
    for (final MapEntry<String, int> e in open.entries)
      if (e.value != 0) '${e.key}(${e.value > 0 ? '+${e.value}' : '${e.value}'})',
  ];
  if (unbalanced.isNotEmpty) {
    issues.add(HtmlIssue('warn', '标签没配平：${unbalanced.join(' ')}'));
  }

  final int styleBlocks = RegExp(r'<style\b', caseSensitive: false).allMatches(html).length;
  final int linkTags = RegExp('<link\\b[^>]*rel\\s*=\\s*${_q}stylesheet',
          caseSensitive: false)
      .allMatches(html)
      .length;
  if (email && styleBlocks > 0) {
    issues.add(HtmlIssue('warn', '有 $styleBlocks 段 <style>，Gmail 和 Outlook 会整段剥掉'));
  }
  if (email && linkTags > 0) {
    issues.add(HtmlIssue('warn', '有 $linkTags 个外链样式表，邮件客户端一律不加载'));
  }

  final Iterable<RegExpMatch> scripts =
      RegExp(r'<script\b', caseSensitive: false).allMatches(html);
  if (scripts.isNotEmpty) {
    issues.add(HtmlIssue('warn', '有 ${scripts.length} 段 <script>，邮件里不会执行'));
  }

  final int remoteImages = RegExp('<img\\b[^>]*src\\s*=\\s*${_q}https?:',
          caseSensitive: false)
      .allMatches(html)
      .length;
  if (remoteImages > 0) {
    issues.add(HtmlIssue('note', '有 $remoteImages 张外链图片，多数客户端默认不加载'));
  }

  final int remoteFonts = RegExp(r'@font-face|fonts\.googleapis|fonts\.gstatic',
          caseSensitive: false)
      .allMatches(html)
      .length;
  if (remoteFonts > 0) {
    issues.add(HtmlIssue('note', '引了外部字体，多半落回系统字体'));
  }

  final List<String> wide = <String>[];
  final RegExp fixed = RegExp('width\\s*[:=]\\s*$_q(\\d{3,4})', caseSensitive: false);
  for (final RegExpMatch m in fixed.allMatches(html)) {
    final int value = int.tryParse(m.group(1) ?? '') ?? 0;
    if (value > 640) wide.add('${m.group(1)}px');
  }
  if (wide.isNotEmpty) {
    issues.add(HtmlIssue('note', '有 ${wide.length} 处宽度超过 640，窄屏会横向溢出（最大 ${wide.first}）'));
  }

  if (elements > 0 && email && styled / elements < 0.5) {
    issues.add(HtmlIssue(
      'note',
      '带行内样式的标签只有 ${(styled / elements * 100).round()}%，邮件里可能变成裸排版',
    ));
  }

  if (html.trim().isEmpty) {
    issues.add(const HtmlIssue('warn', '文件是空的'));
  }

  return HtmlReport(
    bytes: html.length,
    elements: elements,
    inlineStyled: styled,
    issues: issues,
  );
}

/// 把体检结果写成人看的一段话。
String htmlReportText(HtmlReport report, {String path = ''}) {
  final StringBuffer b = StringBuffer();
  if (path.isNotEmpty) b.writeln('$path');
  b.writeln(
    '${report.bytes} 字符 · ${report.elements} 个标签 · '
    '其中 ${report.inlineStyled} 个带行内样式（${(report.inlineRate * 100).round()}%）',
  );
  if (report.issues.isEmpty) {
    b.write('没发现会被剥掉或者撑破的地方。');
    return b.toString();
  }
  for (final HtmlIssue i in report.issues) {
    b.writeln('${i.level == 'warn' ? '要改' : '留意'}：${i.text}');
  }
  return b.toString().trimRight();
}
