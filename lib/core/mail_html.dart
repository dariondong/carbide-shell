/// 一封信的 HTML 版：纯函数，不碰文件、不碰网络，也不 import Flutter。
library;

/// 同一封信的 HTML 版：还是那份文字，只是排开，断行都留着。
///
/// 跟界面同一套颜色（纸白、墨色、一抹蓝），样式全写在行内，邮件客户端认得的就这些。
/// 第一段当结论加粗，机器和时间那一段收成小字，剩下的原样铺开。
String mailHtml(String text) {
  final StringBuffer b = StringBuffer()
    ..write('<!DOCTYPE html><html><head><meta charset="utf-8">')
    ..write('<meta name="viewport" content="width=device-width,initial-scale=1">')
    ..write('</head>')
    ..write('<body style="margin:0;padding:22px 16px;background:#FAF9F6;'
        'font-family:-apple-system,BlinkMacSystemFont,\'Segoe UI\',\'PingFang SC\','
        '\'Hiragino Sans GB\',\'Microsoft YaHei\',sans-serif;'
        'font-size:15px;line-height:1.75;color:#1A1C1F;">')
    ..write('<div style="max-width:560px;margin:0 auto;background:#FFFFFF;'
        'border:1px solid #ECEAE4;border-radius:14px;padding:20px 22px;">');
  final List<String> blocks = text
      .replaceAll('\r\n', '\n')
      .split(RegExp(r'\n[ \t]*\n'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();
  for (int i = 0; i < blocks.length; i += 1) {
    final String block = blocks[i];
    final bool head = i == 0 && blocks.length > 1;
    final String extra = head
        ? 'font-size:16px;font-weight:600;'
        : block.startsWith('机器：')
            ? 'font-size:12.5px;color:#6E7681;line-height:1.9;'
            : '';
    b
      ..write('<p style="margin:0 0 12px;white-space:pre-wrap;$extra">')
      ..write(_escapeHtml(block))
      ..write('</p>');
  }
  b
    ..write('<div style="margin:14px 0 0;padding-top:12px;'
        'border-top:1px solid #ECEAE4;font-size:12px;color:#9AA0A6;">'
        'Carbide Shell 碳壳</div>')
    ..write('</div></body></html>');
  return b.toString();
}

String _escapeHtml(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
