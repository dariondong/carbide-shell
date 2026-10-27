/// 在一份原文里换掉一段，要求它只出现一次。纯函数，不碰文件。
///
/// 改配置最容易出的事是「凭记忆整段回写」：漏一行就是配置损坏。
/// 这里只认唯一匹配，零处或者多处都直接报错，调用方想写错都难。
library;

/// 换完的结果：要么有 [text]，要么有 [error]。
class PatchPlan {
  const PatchPlan({this.text = '', this.error = '', this.at = -1});

  /// 换好的全文。出错时是空串。
  final String text;

  /// 没换成的原因。
  final String error;

  /// 那一段在原文里的位置，预览时用来讲清楚改在哪。
  final int at;

  bool get ok => error.isEmpty;
}

/// 把 [source] 里唯一的那一处 [oldText] 换成 [newText]。
///
/// 找不到、或者不止一处，都返回带 [error] 的结果，一个字都不改。
PatchPlan planPatch(String source, String oldText, String newText) {
  if (oldText.isEmpty) {
    return const PatchPlan(error: 'old_string 是空的，没法确定改哪一处。');
  }
  final int first = source.indexOf(oldText);
  if (first < 0) {
    return PatchPlan(error: '文件里没有这段：${_clip(oldText)}');
  }
  final int second = source.indexOf(oldText, first + 1);
  if (second >= 0) {
    final int count = _count(source, oldText);
    return PatchPlan(
      error: '这段在文件里出现了 $count 次，不知道该改哪一处。'
          '把 old_string 写长一点，带上前后文，让它只剩一处。',
    );
  }
  return PatchPlan(
    text: source.replaceRange(first, first + oldText.length, newText),
    at: first,
  );
}

/// 这一处改在第几行（从 1 数），预览里报给人看。
int lineOf(String source, int at) {
  if (at <= 0) return 1;
  int line = 1;
  final int end = at > source.length ? source.length : at;
  for (int i = 0; i < end; i += 1) {
    if (source.codeUnitAt(i) == 10) line += 1;
  }
  return line;
}

int _count(String source, String needle) {
  int n = 0;
  int from = 0;
  while (true) {
    final int hit = source.indexOf(needle, from);
    if (hit < 0) return n;
    n += 1;
    from = hit + needle.length;
  }
}

String _clip(String text) {
  final String flat = text.replaceAll('\n', '\\n');
  return flat.length > 60 ? '${flat.substring(0, 60)}…' : flat;
}
