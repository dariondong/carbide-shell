import 'core/agent.dart';
import 'core/conversation.dart';
import 'core/journal.dart';
import 'core/memory.dart';
import 'core/models.dart';
import 'core/policy.dart';
import 'core/tools.dart';
import 'data/hosts.dart';
import 'data/llm_settings.dart';
import 'data/secrets.dart';
import 'data/settings.dart';
import 'tools/http_tool.dart';
import 'tools/local_tools.dart';
import 'tools/ssh_tools.dart';

/// One conversation's live pieces: its loop and the memory file it writes.
class AgentSession {
  const AgentSession({required this.loop, required this.memory});

  final AgentLoop loop;
  final MemoryStore memory;
}

/// Everything the UI needs, built once at startup.
class AppServices {
  AppServices({
    required this.hosts,
    required this.secrets,
    required this.settings,
    required this.policy,
    required this.pool,
    required this.memory,
    required this.conversations,
    required this.workspace,
  });

  final HostStore hosts;
  final SecretStore secrets;
  final SettingsStore settings;
  final ApprovalPolicy policy;
  final SshPool pool;
  final MemoryBook memory;
  final ConversationStore conversations;
  final String workspace;

  /// Tools are per session: `remember` must write into this conversation's
  /// memory file, and a single-host conversation only ever sees that host.
  Future<AgentSession> sessionFor(Conversation c) async {
    final MemoryStore store = await memory.open(c.scope);
    final ToolRegistry registry = ToolRegistry()
      ..register(SshExecTool(pool, hosts))
      ..register(SshSftpTool(pool, hosts))
      ..register(HttpTool(settings))
      ..register(FileTool())
      ..register(RememberTool(store));
    if (isDesktopPlatform) {
      registry.register(LocalExecTool());
    }
    final AgentLoop loop = AgentLoop(
      llm: SettingsLlmProvider(settings, secrets),
      registry: registry,
      policy: policy,
      journal: FileJournal(conversations.journalOf(c)),
      context: ToolContext(workspace: workspace, desktop: isDesktopPlatform),
      maxSteps: settings.value.maxSteps,
      maxContextChars: settings.value.contextChars,
      messages: c.messages,
      environment: () => environmentText(hosts, workspace, memory, c),
    );
    loop.extraSystem = settings.value.extraPrompt;
    loop.systemPrompt = promptFor(settings, c);
    return AgentSession(loop: loop, memory: store);
  }

  /// Rebuild the transcript on disk. Called after every turn.
  Future<void> persist(Conversation c) => conversations.save(c);
}

/// 这个对话该用哪份系统提示词：对话自己的优先，然后是设置里的，都没有就用内置那份。
String promptFor(SettingsStore settings, Conversation c) {
  final String own = c.systemPrompt.trim();
  if (own.isNotEmpty) return own;
  final String shared = settings.value.systemPrompt.trim();
  return shared.isEmpty ? kSystemPrompt : shared;
}

String environmentText(
  HostStore hosts,
  String workspace,
  MemoryBook memory,
  Conversation c,
) {
  final StringBuffer b = StringBuffer('\n当前环境\n');
  b.writeln(
      '- 平台：${describePlatform()}。${isDesktopPlatform ? '可以执行本地命令。' : '不能执行本地命令，local_exec 不可用。'}');
  b.writeln('- 工作目录：$workspace');

  final List<HostEntry> visible = c.multiHost
      ? hosts.hosts
      : hosts.hosts.where((HostEntry h) => h.id == c.hostId).toList();

  if (visible.isEmpty) {
    b.writeln('- 这台机器上没有可用的主机，需要用户先在主机页添加。');
  } else {
    b.writeln('- 可用的主机（ssh_exec 的 host 只能用这些名字）：');
    for (final HostEntry h in visible) {
      b.writeln('  ${h.name} = ${h.address}');
    }
    if (!c.multiHost) {
      b.writeln('- 这个对话只管 ${visible.first.name}，别的机器不归它管。');
    }
  }

  final String known = memory.render(<String>[MemoryBook.globalScope, c.scope]);
  if (known.isNotEmpty) {
    b.write('\n');
    b.write(known);
  }
  return b.toString();
}
