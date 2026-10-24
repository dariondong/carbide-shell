import 'models.dart';

/// Decides which tool calls run, which ask, and which are refused.
class ApprovalPolicy {
  ApprovalPolicy({this.mode = ApprovalMode.autoRead, List<String>? patterns})
      : patterns = patterns ?? defaultDangerous;

  ApprovalMode mode;

  /// Case-insensitive patterns matched against a call's summary.
  final List<String> patterns;

  /// Commands that never run, whatever the mode says.
  static const List<String> defaultDangerous = <String>[
    r'\brm\s+-[a-zA-Z]*[rf]',
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
  ];

  ApprovalVerdict verdict(ToolRisk risk, String summary) {
    if (summary.isNotEmpty && isDangerous(summary)) {
      return ApprovalVerdict.deny;
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

  bool isDangerous(String summary) {
    for (final String p in patterns) {
      if (RegExp(p, caseSensitive: false).hasMatch(summary)) {
        return true;
      }
    }
    return false;
  }
}
