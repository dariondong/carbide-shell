/// Shared value types for the agent core. Nothing here imports Flutter.
library;

/// How much damage a tool call can do.
enum ToolRisk {
  /// Reads only. Runs without asking.
  read,

  /// Changes something. Asks first unless the policy says otherwise.
  write,
}

/// When the loop must stop and ask the user.
enum ApprovalMode {
  /// Read tools run, write tools ask. Default.
  autoRead,

  /// Everything runs. The user opted out of confirmations.
  autoAll,

  /// Every tool call asks.
  askAll,
}

/// What the policy says about one call.
enum ApprovalVerdict { allow, ask, deny }

enum LlmRole { system, user, assistant, tool }

class LlmUsage {
  const LlmUsage({this.prompt = 0, this.completion = 0});

  final int prompt;
  final int completion;

  int get total => prompt + completion;
}

class LlmToolCall {
  const LlmToolCall({required this.id, required this.name, required this.args});

  final String id;
  final String name;
  final Map<String, Object?> args;
}

class LlmMessage {
  const LlmMessage.user(this.text, {this.images = const <String>[]})
      : role = LlmRole.user,
        calls = const <LlmToolCall>[],
        toolCallId = '',
        toolName = '',
        failed = false;

  const LlmMessage.assistant(this.text, {this.calls = const <LlmToolCall>[]})
      : role = LlmRole.assistant,
        images = const <String>[],
        toolCallId = '',
        toolName = '',
        failed = false;

  const LlmMessage.toolResult({
    required this.text,
    required this.toolCallId,
    required this.toolName,
    this.failed = false,
  })  : role = LlmRole.tool,
        calls = const <LlmToolCall>[],
        images = const <String>[];

  final LlmRole role;
  final String text;
  final List<LlmToolCall> calls;
  final String toolCallId;
  final String toolName;
  final bool failed;

  /// Data URLs (`data:image/png;base64,…`) the model should look at.
  final List<String> images;

  bool get isTool => role == LlmRole.tool;
}

class LlmReply {
  const LlmReply({
    this.text = '',
    this.calls = const <LlmToolCall>[],
    this.usage = const LlmUsage(),
  });

  final String text;
  final List<LlmToolCall> calls;
  final LlmUsage usage;

  bool get wantsTools => calls.isNotEmpty;
}

/// What the model is told about one tool.
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.schema,
  });

  final String name;
  final String description;
  final Map<String, Object?> schema;
}

class ToolOutcome {
  const ToolOutcome({
    this.ok = true,
    this.stdout = '',
    this.stderr = '',
    this.exitCode,
    this.error = '',
    this.meta = const <String, Object?> {},
  });

  const ToolOutcome.success({
    String stdout = '',
    String stderr = '',
    int? exitCode,
    Map<String, Object?> meta = const <String, Object?>{},
  })  : ok = true,
        stdout = stdout,
        stderr = stderr,
        exitCode = exitCode,
        error = '',
        meta = meta;

  const ToolOutcome.failure(String message)
      : ok = false,
        stdout = '',
        stderr = '',
        exitCode = null,
        error = message,
        meta = const <String, Object?>{};

  final bool ok;
  final String stdout;
  final String stderr;
  final int? exitCode;
  final String error;
  final Map<String, Object?> meta;
}

/// Everything a tool may know about the machine it runs on.
class ToolContext {
  const ToolContext({
    required this.workspace,
    required this.desktop,
    this.timeout = const Duration(seconds: 15),
  });

  /// Directory the agent may write inside.
  final String workspace;

  /// True on Windows, macOS and Linux. False on Android and iOS.
  final bool desktop;

  final Duration timeout;

  ToolContext copyWith({String? workspace}) => ToolContext(
        workspace: workspace ?? this.workspace,
        desktop: desktop,
        timeout: timeout,
      );
}

String readString(Map<String, Object?> args, String key, {String fallback = ''}) {
  final Object? v = args[key];
  return v is String ? v : fallback;
}

int readInt(Map<String, Object?> args, String key, {int fallback = 0}) {
  final Object? v = args[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}
