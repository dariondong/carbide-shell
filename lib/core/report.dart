/// 把一组数字和几段文字排成一份 HTML 报告。纯函数，不碰文件也不联网。
///
/// 一份报告的内容本来只是十几个数字加几段话，每次都手写行内样式的表格既费 token
/// 又容易前后不一致。这里把排版固定下来，调用方只给内容。
library;

/// 一个指标：大号数字 + 小字说明。
class ReportMetric {
  const ReportMetric({required this.value, required this.label, this.tone = 'plain'});

  final String value;
  final String label;

  /// `ok` / `warn` / `bad` / `plain` / `accent`。
  final String tone;
}

/// 报告里的一段。带 `level` 的是问题条目，`kind: note` 的是提示框。
class ReportSection {
  const ReportSection({
    this.level = '',
    this.kind = '',
    this.color = '',
    required this.heading,
    this.body = '',
  });

  /// `P0` / `P1` / `P2`，空着就不出标签。
  final String level;

  /// `note` 是提示框，其余当普通条目。
  final String kind;

  /// 提示框的颜色：`amber` / `red` / `green` / `blue`。
  final String color;

  final String heading;
  final String body;
}

/// 纸白、墨色、一抹蓝，加红橙绿三个状态色。和界面是同一套。
const String _ink = '#1A1C1F';
const String _body = '#3A4048';
const String _grey = '#6E7681';
const String _grey2 = '#9AA0A6';
const String _paper = '#F4F3EF';
const String _card = '#FFFFFF';
const String _rule = '#ECEAE4';
const String _blue = '#3355E8';

const Map<String, String> _toneColor = <String, String>{
  'ok': '#1E7B4F',
  'warn': '#B26A00',
  'bad': '#C0281C',
  'accent': _blue,
  'plain': _ink,
};

const Map<String, String> _levelTone = <String, String>{
  'P0': 'bad',
  'P1': 'warn',
  'P2': 'plain',
};

const Map<String, String> _noteTone = <String, String>{
  'amber': 'warn',
  'red': 'bad',
  'green': 'ok',
  'blue': 'accent',
};

/// 排一份报告。
///
/// [template] 三种：`report` 网页版（多一段样式，手机上好读）、
/// `email` 邮件版（纯 table + 全行内样式，Gmail / Outlook 都认）、
/// `plain` 纯文本（Markdown，贴在聊天里或者进通知邮件）。
String renderReport({
  String template = 'report',
  required String title,
  String subtitle = '',
  List<ReportMetric> metrics = const <ReportMetric>[],
  List<ReportSection> sections = const <ReportSection>[],
  String footer = '',
}) {
  final String kind = template.trim().toLowerCase();
  if (kind == 'plain') {
    return _plainText(title, subtitle, metrics, sections, footer);
  }
  return _html(kind == 'email', title, subtitle, metrics, sections, footer);
}

String _html(
  bool email,
  String title,
  String subtitle,
  List<ReportMetric> metrics,
  List<ReportSection> sections,
  String footer,
) {
  final StringBuffer b = StringBuffer()
    ..write('<!DOCTYPE html>\n<html lang="zh">\n<head>\n')
    ..write('<meta charset="utf-8">\n')
    ..write('<meta name="viewport" content="width=device-width,initial-scale=1">\n')
    ..write('<title>${escapeText(title)}</title>\n');
  if (!email) {
    b.write('<style>\n'
        '  body { margin: 0; background: $_paper; }\n'
        '  .wrap { width: 640px; max-width: 100%; }\n'
        '  .metric { width: 25%; }\n'
        '  @media (max-width: 680px) {\n'
        '    .metric { display: block; width: 100%; margin-bottom: 8px; }\n'
        '  }\n'
        '</style>\n');
  }
  b
    ..write('</head>\n')
    ..write('<body style="margin:0;padding:24px 12px;background:$_paper;'
        'font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',\'PingFang SC\','
        '\'Hiragino Sans GB\',\'Microsoft YaHei\',sans-serif;'
        'font-size:15px;line-height:1.75;color:$_ink;">\n')
    ..write('<table role="presentation" width="100%" cellpadding="0" cellspacing="0" '
        'border="0" style="border-collapse:collapse;background:$_paper;">\n'
        '<tr><td align="center" style="padding:0;">\n')
    ..write('<table role="presentation" class="wrap" width="640" cellpadding="0" '
        'cellspacing="0" border="0" style="width:640px;max-width:100%;'
        'background:$_card;border:1px solid $_rule;border-radius:14px;'
        'border-collapse:separate;">\n')
    ..write('<tr><td style="padding:22px 24px 0;">\n')
    ..write('<div style="font-size:20px;font-weight:700;line-height:1.4;color:$_ink;">'
        '${escapeText(title)}</div>\n');
  if (subtitle.trim().isNotEmpty) {
    b.write('<div style="margin-top:6px;font-size:13px;color:$_grey;">'
        '${escapeText(subtitle)}</div>\n');
  }
  b.write('</td></tr>\n');

  if (metrics.isNotEmpty) {
    b.write('<tr><td style="padding:14px 24px 0;">\n');
    for (int start = 0; start < metrics.length; start += 4) {
      final List<ReportMetric> row = metrics.sublist(
        start,
        start + 4 > metrics.length ? metrics.length : start + 4,
      );
      b.write('<table role="presentation" width="100%" cellpadding="0" '
          'cellspacing="0" border="0" style="border-collapse:separate;'
          'border-spacing:6px 0;margin:0 -6px;"><tr>\n');
      for (final ReportMetric m in row) {
        final String color = _toneColor[m.tone] ?? _ink;
        b.write('<td class="metric" width="25%" align="center" '
            'style="width:25%;padding:12px 8px;background:#FAF9F6;'
            'border-radius:10px;text-align:center;">'
            '<div style="font-size:22px;font-weight:700;line-height:1.3;color:$color;">'
            '${escapeText(m.value)}</div>'
            '<div style="margin-top:4px;font-size:12px;color:$_grey;">'
            '${escapeText(m.label)}</div></td>\n');
      }
      b.write('</tr></table>\n');
    }
    b.write('</td></tr>\n');
  }

  if (sections.isNotEmpty) {
    b.write('<tr><td style="padding:6px 24px 0;">\n');
    for (final ReportSection s in sections) {
      final String head = escapeText(s.heading);
      if (s.kind == 'note' || s.level.isEmpty && s.kind.isNotEmpty) {
        final String tone = _noteTone[s.color] ?? 'accent';
        final String color = _toneColor[tone] ?? _blue;
        b.write('<div style="margin:14px 0 0;padding:12px 14px;'
            'background:#FAF9F6;border-left:3px solid $color;border-radius:8px;">\n');
        if (head.isNotEmpty) {
          b.write('<div style="font-size:14px;font-weight:600;color:$color;">'
              '$head</div>\n');
        }
        if (s.body.trim().isNotEmpty) {
          b.write('<div style="margin-top:4px;font-size:14px;line-height:1.7;'
              'color:$_body;white-space:pre-wrap;">${escapeText(s.body)}</div>\n');
        }
        b.write('</div>\n');
        continue;
      }
      final String tone = _levelTone[s.level.toUpperCase()] ?? '';
      b.write('<div style="margin:16px 0 0;">\n');
      b.write('<div style="font-size:15px;font-weight:600;line-height:1.6;color:$_ink;">');
      if (tone.isNotEmpty) {
        b.write('<span style="display:inline-block;padding:1px 7px;border-radius:6px;'
            'background:${_toneColor[tone]};color:#FFFFFF;font-size:11px;font-weight:700;'
            'letter-spacing:0.5px;margin-right:8px;vertical-align:2px;">'
            '${escapeText(s.level.toUpperCase())}</span>');
      }
      b.write('$head</div>\n');
      if (s.body.trim().isNotEmpty) {
        b.write('<div style="margin-top:6px;font-size:14px;line-height:1.75;'
            'color:$_body;white-space:pre-wrap;">${escapeText(s.body)}</div>\n');
      }
      b.write('</div>\n');
    }
    b.write('</td></tr>\n');
  }

  b.write('<tr><td style="padding:18px 24px 22px;">\n');
  if (footer.trim().isNotEmpty) {
    b.write('<div style="border-top:1px solid $_rule;padding-top:12px;'
        'font-size:12px;color:$_grey2;line-height:1.7;">${escapeText(footer)}</div>\n');
  } else {
    b.write('<div style="border-top:1px solid $_rule;padding-top:12px;'
        'font-size:12px;color:$_grey2;">Carbide Shell 碳壳</div>\n');
  }
  b
    ..write('</td></tr>\n')
    ..write('</table>\n')
    ..write('</td></tr>\n</table>\n')
    ..write('</body>\n</html>\n');
  return b.toString();
}

String _plainText(
  String title,
  String subtitle,
  List<ReportMetric> metrics,
  List<ReportSection> sections,
  String footer,
) {
  final StringBuffer b = StringBuffer('# $title\n');
  if (subtitle.trim().isNotEmpty) b.write('\n$subtitle\n');
  if (metrics.isNotEmpty) {
    b.write('\n');
    for (final ReportMetric m in metrics) {
      b.write('- ${m.label}：${m.value}\n');
    }
  }
  for (final ReportSection s in sections) {
    b.write('\n');
    if (s.kind == 'note') {
      b.write('> ${s.heading}${s.body.trim().isEmpty ? '' : '：${s.body.trim()}'}\n');
      continue;
    }
    final String tag = s.level.isEmpty ? '' : '[${s.level.toUpperCase()}] ';
    b.write('## $tag${s.heading}\n');
    if (s.body.trim().isNotEmpty) b.write('\n${s.body.trim()}\n');
  }
  if (footer.trim().isNotEmpty) b.write('\n---\n\n$footer\n');
  return b.toString();
}

/// HTML 里这几个字符必须换掉，不然一段命令输出就能把整页结构撑坏。
String escapeText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
