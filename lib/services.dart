import 'core/agent.dart';
import 'core/conversation.dart';
import 'core/journal.dart';
import 'core/memory.dart';
import 'core/models.dart';
import 'core/policy.dart';
import 'core/tools.dart';
import 'data/hosts.dart';
import 'data/llm_settings.dart';
import 'data/mail.dart';
import 'data/secrets.dart';
import 'data/settings.dart';
import 'data/tasks.dart';
import 'data/temp_files.dart';
import 'data/usage.dart';
import 'data/watch.dart';
import 'tools/ask_tool.dart';
import 'tools/clock_tool.dart';
import 'tools/diff_tool.dart';
import 'tools/host_tools.dart';
import 'tools/task_tools.dart';
import 'tools/http_tool.dart';
import 'tools/local_tools.dart';
import 'tools/mail_tool.dart';
import 'tools/notify_tool.dart';
import 'tools/probe_tool.dart';
import 'tools/render_tool.dart';
import 'tools/report_tool.dart';
import 'tools/ssh_tools.dart';
import 'tools/status_tools.dart';
import 'tools/temp_tools.dart';

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
    required this.tasks,
    required this.watches,
    required this.usage,
    required this.mail,
    required this.workspace,
    required this.files,
  });

  final HostStore hosts;
  final SecretStore secrets;
  final SettingsStore settings;
  final ApprovalPolicy policy;
  final SshPool pool;
  final MemoryBook memory;
  final ConversationStore conversations;

  /// 定时任务与资源监听的清单：模型也能往里写，所以要在这里够得着。
  final TaskStore tasks;
  final WatchStore watches;

  /// 模型用量账本。
  final UsageStore usage;

  /// 邮箱通知：定时任务跑完、监听过线时顺手发一封。
  final MailStore mail;
  final String workspace;

  /// 临时文件区：模型写文件、用户往里放文件、两个都把文件传到主机。
  final TempFiles files;

  /// Tools are per session: `remember` must write into this conversation's
  /// memory file, and a single-host conversation only ever sees that host.
  Future<AgentSession> sessionFor(Conversation c) async {
    final MemoryStore store = await memory.open(c.scope);
    final ToolRegistry registry = ToolRegistry()
      ..register(SshExecTool(pool, hosts))
      ..register(SshSftpTool(pool, hosts))
      ..register(HttpTool(settings))
      ..register(ClockTool())
      ..register(FileTool())
      ..register(TempFileTool(files))
      ..register(TempUploadTool(files: files, pool: pool, hosts: hosts))
      ..register(TempDownloadTool(files: files, pool: pool, hosts: hosts))
      ..register(RememberTool(store))
      ..register(AskTool())
      ..register(NotifyTool())
      ..register(MailSendTool(mail, files: files))
      ..register(ReportRenderTool(files))
      ..register(RenderCheckTool(files))
      ..register(ProbeTool())
      ..register(RemoteDiffTool(pool: pool, hosts: hosts, files: files))
      ..register(TaskAddTool(tasks: tasks, hosts: hosts))
      ..register(WatchAddTool(watches: watches, hosts: hosts))
      // 已经排好的东西得看得见、停得掉、删得掉，不然模型只能一直往里加
      ..register(HostListTool(
          hosts: hosts, onlyHostId: c.multiHost ? '' : c.hostId))
      ..register(TaskListTool(
          tasks: tasks, hosts: hosts, onlyHostId: c.multiHost ? '' : c.hostId))
      ..register(WatchListTool(
          watches: watches, hosts: hosts, onlyHostId: c.multiHost ? '' : c.hostId))
      ..register(TaskControlTool(tasks))
      ..register(WatchControlTool(watches));
    if (isDesktopPlatform) {
      registry.register(LocalExecTool());
    }
    // Advance Master 才拿得到「加主机 / 删主机」这两个写口子。
    if (c.advanceMaster) {
      registry.register(AddHostTool(hosts: hosts, secrets: secrets, pool: pool));
      registry.register(RemoveHostTool(hosts: hosts, secrets: secrets));
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
  b.writeln('- 工作目录也是临时文件区：$workspace');
  b.writeln(
      '  写、列、读、删文件用 temp_file；要把这里的文件传到主机上用 temp_upload。');
  final DateTime now = DateTime.now();
  const List<String> week = <String>['一', '二', '三', '四', '五', '六', '日'];
  String two(int n) => n.toString().padLeft(2, '0');
  // 只写日期，不写几点几分：这一行在系统提示词里，每过一分钟就变一个字，
  // 整段前缀的缓存每轮都作废。要准确时刻用 clock 工具。
  b.writeln('- 今天是：${now.year}-${two(now.month)}-${two(now.day)}，'
      '星期${week[now.weekday - 1]}（设备本地时间）。排日期按这个算，要几点几分用 clock 工具。');

  final List<HostEntry> visible = c.multiHost
      ? hosts.hosts
      : hosts.hosts.where((HostEntry h) => h.id == c.hostId).toList();

  if (c.advanceMaster) {
    b.writeln('- 这个对话是 Advance Master：管全部主机，可以用 host_add 把新主机写进列表。'
        '地址、账号、密码或私钥先问清楚，不要自己编。');
  }

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
