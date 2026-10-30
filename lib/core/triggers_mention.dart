/// 一条通知是不是冲着「我」来的。
///
/// 群里的脏话不一定是对谁说的：有人在骂街、有人在转述、有人在跟别人斗嘴，
/// 都不该由我来接话。只有明确 @ 了我，或者就是单独发给我的，才算。
///
/// 认得出来的几种写法（微信群里的 @ 实际长这样）：
/// - `@Darion（BG7LZQ) BY7080SWL`  —— 微信自动带上的「昵称（呼号）备注」格式
/// - `@Darion` / `@Darion ` —— 直接叫昵称
/// - `@全体成员` —— 所有人，不算针对我，但也不算别人
///
/// 私聊的标题就是对方昵称，正文没有 `@`；这时候只要是我自己的会话就算。
class MessageTarget {
  const MessageTarget({
    required this.atMe,
    required this.reason,
    this.mentioned = false,
  });

  /// 明确 @ 了我。
  final bool atMe;

  /// 是群消息（不是私聊）。
  final bool mentioned;

  /// 说给人听的理由。
  final String reason;

  static const MessageTarget notAtMe = MessageTarget(atMe: false, reason: '');
}

/// 昵称、呼号、备注名里出现任意一个就算 @ 了我。
///
/// 主人身上可能有好几个名字：微信昵称 `Darion`、呼号 `BG7LZQ`、
/// 群备注 `Darion（BG7LZQ) BY7080SWL`。任一命中即可。
bool mentionsMe(String text, List<String> myNames) {
  if (text.isEmpty || myNames.isEmpty) return false;
  for (final String name in myNames) {
    final String n = name.trim();
    if (n.isEmpty) continue;
    if (_atFollows(text, n)) return true;
  }
  return false;
}

/// `@` 后面紧跟着这个名字才算数。
///
/// 不能光看「文中出现了我的名字」——比如有人转发我之前发的消息，
/// 或者群里提到「BG7LZQ 的电台」，那都不是在叫我。
/// 微信的 @ 后面可能带一个全角空格，所以空格也算边界。
bool _atFollows(String text, String name) {
  final String lowerText = text.toLowerCase();
  final String lowerName = name.toLowerCase();
  int from = 0;
  while (from < lowerText.length) {
    final int at = lowerText.indexOf('@', from);
    if (at < 0) return false;
    final int start = at + 1;
    // 跳过 @ 后的空格（微信会插一个全角空格）。
    int cut = start;
    while (cut < lowerText.length && (lowerText[cut] == ' ' || lowerText[cut] == '\u3000')) {
      cut++;
    }
    final String after = lowerText.substring(cut);
    if (after.startsWith(lowerName)) {
      // 名字后面必须是边界，不能是「BG7LZQabc」这种。
      final int end = cut + lowerName.length;
      if (end >= lowerText.length) return true;
      final String c = lowerText[end];
      final bool boundary = c == ' ' ||
          c == '\u3000' ||
          c == ':' ||
          c == '：' ||
          c == ',' ||
          c == '，' ||
          c == '(' ||
          c == '（' ||
          c == ')' ||
          c == '）' ||
          c == '[' ||
          c == '[' ||
          c == ']' ||
          c == ']' ||
          c == '\n';
      if (boundary) return true;
    }
    from = at + 1;
  }
  return false;
}

/// 群名还是私聊？微信的群标题大多带括号或「群」字，私聊就是一个人名。
///
/// 认不准的时候按「可能是群」处理更安全：宁可漏掉，也不误伤。
bool looksLikeGroup(String title) {
  final String t = title.trim();
  if (t.isEmpty) return true;
  if (t.contains('[') || t.contains('（') || t.contains('(')) return true;
  if (t.contains('群')) return true;
  if (t.endsWith(')')) return true;
  if (t.endsWith('）')) return true;
  // 微信群名常带 [群主昵称]、[表情] 之类的后缀，也有「群聊」以外的怪名字。
  // 认不准就当群：宁可漏掉，也别替别人接话。
  if (t.contains(']') || t.contains('】')) return true;
  // 群名常带版本号一样的后缀（MC 26.2、粤西 2.4G）：数字后面跟着数字、
  // 或者数字前面有个点，就当群。人的昵称很少长这样。
  if (RegExp(r'\d+\.\d+').hasMatch(t)) return true;
  // 「粤西无线电爱好者」这种：地名 + 兴趣圈子的名字，多半是群。
  // 拿不准的一律当群：宁可漏掉，也别替别人接话。
  if (t.length >= 6 && t.contains('爱好者')) return true;
  // 「设备互联 全场景音乐服务」这种系统群名：多个词拼起来。
  // 但人的昵称也常是「苏国佑 云浮新兴 BG7PGW」这样带呼号的，
  // 昵称里有呼号（BG/BH/BI + 数字）就当人，别当群。
  if (RegExp(r'[\u4e00-\u9fa5]{2,}\s+[\u4e00-\u9fa5]{2,}').hasMatch(t) &&
      !_hasCallsign(t)) {
    return true;
  }
  return false;
}

/// 文字里有没有呼号（BG7LZQ、BH6RIZ、BI1IZF 这类）。
bool _hasCallsign(String text) {
  return RegExp(r'\b[B][GHIK]\d?[0-9][A-Z0-9]{1,4}\b', caseSensitive: false).hasMatch(text);
}

/// 判断一条通知是不是冲着主人来的。
///
/// - 私聊：直接对我说的，命中。
/// - 群消息：只有明确 @ 了我才算；@全体成员不算。
/// - 认不准是不是群：也要求明确 @ 我，免得替别人接话。
MessageTarget judgeTarget({
  required String title,
  required String text,
  required List<String> myNames,
}) {
  final bool group = looksLikeGroup(title);
  final bool at = mentionsMe(text, myNames);
  if (at) {
    return MessageTarget(atMe: true, mentioned: true, reason: '明确 @ 了我');
  }
  if (!group) {
    return MessageTarget(atMe: true, mentioned: false, reason: '单独发给我的');
  }
  return MessageTarget(
    atMe: false,
    mentioned: false,
    reason: '群里的话，没有 @ 我',
  );
}
