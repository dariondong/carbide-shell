import 'models.dart';

/// 摘要那一条开头的标记。看见它就知道这条是压缩出来的，不是模型当场的回答。
const String kCompactMark = '【更早的对话摘要】';

/// 收摘要时给模型的那份系统话。
const String kCompactSystem = '你在替一场很长的对话做整理。'
    '只输出摘要本身，一段连续的文字，最多四百字。不要标题，不要列表符号，不要客套话。';

/// 一条记录在预算里算多少字。正文、工具参数、图片都算。
///
/// 和 `core/conversation.dart` 的 `messageWeight` 是同一把尺子，这里为了不让
/// 这个文件依赖磁盘那一层，单独放了一份最小实现。
int _weight(LlmMessage m) {
  int n = m.text.length + 24;
  for (final LlmToolCall c in m.calls) {
    n += c.name.length + 16;
    for (final Object? v in c.args.values) {
      if (v is String) n += v.length;
    }
  }
  for (final String url in m.images) {
    n += url.length;
  }
  return n;
}

String _clip(String text, int max) {
  final String one = text.trim();
  if (one.length <= max) return one;
  return '${one.substring(0, max)}…';
}

/// 参数压成一行：`(path: /etc/nginx, host: web-1)`。
String _args(Map<String, Object?> args) {
  if (args.isEmpty) return '';
  final List<String> parts = <String>[];
  for (final MapEntry<String, Object?> e in args.entries) {
    if (parts.length >= 4) break;
    final Object? v = e.value;
    final String text = v is String ? v : '$v';
    parts.add('${e.key}: ${_clip(text, 120)}');
  }
  return '(${parts.join(', ')})';
}

/// 前一段交给模型时问的那段话：把要丢掉的那几条按人话铺开，再要一段摘要。
String compactPrompt(List<LlmMessage> head) {
  final StringBuffer b = StringBuffer();
  for (final LlmMessage m in head) {
    switch (m.role) {
      case LlmRole.user:
        final String text = _clip(m.text, 1200);
        if (text.isNotEmpty) b.writeln('用户：$text');
      case LlmRole.assistant:
        final String text = _clip(m.text, 1200);
        if (text.isNotEmpty) b.writeln('助手：$text');
        for (final LlmToolCall c in m.calls) {
          b.writeln('调用 ${c.name}${_args(c.args)}');
        }
      case LlmRole.tool:
        final String text = _clip(m.text, 400);
        if (text.isNotEmpty) b.writeln('工具 ${m.toolName} 结果：$text');
      case LlmRole.system:
        break;
    }
  }
  b.writeln();
  b.write('把上面这段对话收成一段摘要：做过什么、结论是什么、哪些还没做完、'
      '用户定下的规矩、涉及的主机和路径。只写摘要本身。');
  return b.toString();
}

/// 从哪一条开始留。前面的那一段（`[0, 返回值)`）交给模型收成摘要。
///
/// 尾巴一定从一条用户消息开始：工具结果离开它那条调用，模型读起来就是一句没头没尾的输出。
/// 前面太短、尾巴太短，都不值得压，返回 0。
int compactCut(List<LlmMessage> messages, {int keepChars = 12000}) {
  final int n = messages.length;
  if (n < 6) return 0;
  int acc = 0;
  int start = n;
  for (int i = n - 1; i >= 0; i -= 1) {
    acc += _weight(messages[i]);
    start = i;
    if (acc > keepChars) break;
  }
  // 从估算出来的位置往后找第一条用户消息；往后找不到就往前退一条。
  int at = -1;
  for (int i = start; i < n; i += 1) {
    if (messages[i].role == LlmRole.user) {
      at = i;
      break;
    }
  }
  if (at < 0) {
    for (int i = start - 1; i >= 0; i -= 1) {
      if (messages[i].role == LlmRole.user) {
        at = i;
        break;
      }
    }
  }
  if (at < 0) return 0;
  // 前面至少四条的份量才值得一次模型调用，尾巴至少三条才读得懂。
  if (at < 2 || n - at < 3) return 0;
  int headChars = 0;
  for (int i = 0; i < at; i += 1) {
    headChars += _weight(messages[i]);
  }
  if (headChars < 2000) return 0;
  return at;
}
