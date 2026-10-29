import 'models.dart';

/// Decides which tool calls run, which ask, and which are refused.
///
/// 两档拦：一档是**永远不做**（会把机器或系统本身弄坏），另一档是**先问一句**（删东西、
/// 覆盖这类）。第二档问过就能做，批准卡上会写明这一步会删什么。
class ApprovalPolicy {
  ApprovalPolicy({
    this.mode = ApprovalMode.autoRead,
    List<String>? blocked,
    List<String>? risky,
  })  : blocked = blocked ?? defaultBlocked,
        risky = risky ?? defaultRisky;

  ApprovalMode mode;

  /// 谁按了批准也不执行：这些下去机器就没了。
  final List<String> blocked;

  /// 批准了才做：删除、清库这类，做之前先让人看一眼。
  final List<String> risky;

  /// 命令下去会把机器或系统本身弄坏的那种。
  static const List<String> defaultBlocked = <String>[
    r'\bmkfs',
    r'\bdd\b[^\n]*of\s*=\s*/dev/',
    r'\bshutdown\b',
    r'\breboot\b',
    r'\bpoweroff\b',
    r'\bhalt\b',
    r'>\s*/etc/',
    r'\bchmod\s+-R\s+777\s+/',
    r'\binit\s+0\b',
    r'\b:?\s*\(\s*\)\s*\{.*:\|:',
    // 删到根、删到整个家目录：连问都不问。
    r'\brm\b[^\n]*\s/(\s|\*|$)',
    r'\brm\b[^\n]*\s~(/\*?)?(\s|$)',
  ];

  /// 会删东西、清数据的：要问，但问过就做。
  static const List<String> defaultRisky = <String>[
    r'\brm\b',
    r'\brmdir\b',
    r'\bshred\b',
    r'\bunlink\b',
    r'\bdrop\s+(table|database)\b',
  ];

  ApprovalVerdict verdict(ToolRisk risk, String summary) {
    if (summary.isNotEmpty) {
      if (isBlocked(summary)) return ApprovalVerdict.deny;
      // 删东西这一档不管审批调得多宽都要问一次。
      if (isRisky(summary)) return ApprovalVerdict.ask;
    }
    switch (mode) {
      case ApprovalMode.askAll:
        return ApprovalVerdict.ask;
      case ApprovalMode.autoAll:
        return ApprovalVerdict.allow;
      case ApprovalMode.autoRead:
        return risk == ToolRisk.read ? ApprovalVerdict.allow : ApprovalVerdict.ask;
    }
  }

  bool isBlocked(String summary) => _matches(blocked, summary);

  bool isRisky(String summary) => _matches(risky, summary);

  /// 这一步会不会动到不该动的东西。批准卡靠它在卡上多写一句。
  bool isDangerous(String summary) => isBlocked(summary) || isRisky(summary);

  static bool _matches(List<String> patterns, String summary) {
    for (final String p in patterns) {
      if (RegExp(p, caseSensitive: false).hasMatch(summary)) {
        return true;
      }
    }
    return false;
  }
}
