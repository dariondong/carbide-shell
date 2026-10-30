import 'core/agent.dart';
import 'core/conversation.dart';
import 'core/journal.dart';
import 'core/memory.dart';
import 'core/models.dart';
import 'core/plan.dart';
import 'core/policy.dart';
import 'core/tools.dart';
import 'data/device.dart';
import 'data/env_keys.dart';
import 'data/hosts.dart';
import 'data/llm_settings.dart';
import 'data/mail.dart';
import 'data/secrets.dart';
import 'data/settings.dart';
import 'data/tasks.dart';
import 'data/temp_files.dart';
import 'data/triggers.dart';
import 'data/usage.dart';
import 'data/watch.dart';
import 'tools/app_tools.dart';
import 'tools/ask_tool.dart';
import 'tools/clock_tool.dart';
import 'tools/device_tools.dart';
import 'tools/diff_tool.dart';
import 'tools/env_tool.dart';
import 'tools/host_tools.dart';
import 'tools/task_tools.dart';
import 'tools/http_tool.dart';
import 'tools/local_tools.dart';
import 'tools/net_tool.dart';
import 'tools/mail_read_tool.dart';
import 'tools/mail_tool.dart';
import 'tools/memory_tool.dart';
import 'tools/notify_tool.dart';
import 'tools/param_tool.dart';
import 'tools/plan_tool.dart';
import 'tools/probe_tool.dart';
import 'tools/render_tool.dart';
import 'tools/report_tool.dart';
import 'tools/ssh_tools.dart';
import 'tools/status_tools.dart';
import 'tools/temp_tools.dart';
import 'tools/trigger_tool.dart';
import 'tools/web_tool.dart';

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
    required this.env,
    required this.triggers,
    required this.workspace,
    required this.files,
    DeviceApi? device,
  }) : device = device ?? const PhoneDevice();

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

  /// 环境密钥：名字与日志在本地，值在安全存储里。
  final EnvBook env;

  /// 触发器清单：手机状态、消息通知、定时。
  final TriggerStore triggers;
  final String workspace;

  /// 临时文件区：模型写文件、用户往里放文件、两个都把文件传到主机。
  final TempFiles files;

  /// 手机那一侧的能力。测试里换成假的，工具就不用碰原生。
  final DeviceApi device;

  /// 一项扩展 = 一组工具。哪一项开了，那一组才进模型的清单。
  late final Map<String, List<Tool>> _groupTools = <String, List<Tool>>{
    'device': <Tool>[DeviceInfoTool(device), PhoneStateTool(device)],
    'clipboard': <Tool>[ClipboardTool(device)],
    'launch': <Tool>[OpenUrlTool(), ShareTool(device)],
    'location': <Tool>[WhereAmITool(device)],
    'contacts': <Tool>[FindContactTool(device)],
    'sms': <Tool>[SmsSendTool(device)],
    'notif': <Tool>[NotifyReadTool(device)],
    'apps': <Tool>[OpenAppTool(device), SetAlarmTool(device), SetTimerTool(device)],
    'sound': <Tool>[VolumeTool(device)],
    'usage': <Tool>[AppUsageTool(device)],
  };

  /// 按现在的开关把扩展的工具挂上或摘下来。
  /// 每轮开跑前叫一次，设置里一改，下一句话就生效。
  void syncTools(AgentSession session) {
    for (final MapEntry<String, List<Tool>> e in _groupTools.entries) {
      final bool on = settings.value.toolOn(e.key);
      for (final Tool t in e.value) {
        if (on) {
          session.loop.registry.register(t);
        } else {
          session.loop.registry.unregister(t.name);
        }
      }
    }
  }

  /// Tools are per session: `remember` must write into this conversation's
  /// memory file, and a single-host conversation only ever sees that host.
  Future<AgentSession> sessionFor(Conversation c) async {
    final MemoryStore store = await memory.open(c.scope);
    final ToolRegistry registry = ToolRegistry()
      ..register(SshExecTool(pool, hosts))
      ..register(SshSftpTool(pool, hosts))
      ..register(HttpTool(settings))
      ..register(HttpAllowTool(settings))
      ..register(ClockTool())
      // 联网：走 DeepSeek 的搜索接口，只读，不用点批准。
      ..register(WebSearchTool(
          settings: settings, secrets: secrets, profileId: () => c.profileId))
      ..register(
          WebFetchTool(settings: settings, secrets: secrets, profileId: () => c.profileId))
      ..register(FileTool())
      ..register(TempFileTool(files))
      ..register(TempUploadTool(files: files, pool: pool, hosts: hosts))
      ..register(TempDownloadTool(files: files, pool: pool, hosts: hosts))
      ..register(RememberTool(store))
      ..register(MemoryTool(store))
      ..register(AskTool())
      // 计划写在这张对话上，界面照着它画顶上那张卡。
      ..register(PlanTool(
        plan: c.plan,
        onChanged: (WorkPlan next) {
          c.plan = next;
          // 做完了就把这一张停在当时的位置，后面的新活另起一张。
          if (next.finished) c.planAnchor = c.messages.length;
        },
      ))
      ..register(NotifyTool())
      ..register(EnvListTool(env))
      ..register(EnvSetTool(env))
      ..register(EnvDeleteTool(env))
      ..register(EnvRequestTool(env, settings))
      ..register(MailSendTool(mail, files: files))
      ..register(MailAllowTool(mail))
      ..register(MailInboxTool(mail))
      ..register(MailReadTool(mail))
      ..register(ReportRenderTool(files))
      ..register(RenderCheckTool(files))
      ..register(ProbeTool())
      ..register(RemoteDiffTool(pool: pool, hosts: hosts, files: files))
      ..register(TaskAddTool(tasks: tasks, hosts: hosts))
      ..register(WatchAddTool(watches: watches, hosts: hosts))
      // 已经排好的东西得看得见、停得掉、删得掉，不然模型只能一直往里加
      // 参数调节：模型提，用户点批准才改；锁着的不动。
      ..register(TuneParamTool(
        settings: settings,
        profileId: () => profileOf(settings.value, c.profileId).id,
        save: settings.save,
      ))
      ..register(HostListTool(
          hosts: hosts, onlyHostId: c.multiHost ? '' : c.hostId))
      ..register(TaskListTool(
          tasks: tasks, hosts: hosts, onlyHostId: c.multiHost ? '' : c.hostId))
      ..register(WatchListTool(
          watches: watches, hosts: hosts, onlyHostId: c.multiHost ? '' : c.hostId))
      ..register(TaskControlTool(tasks))
      ..register(WatchControlTool(watches))
      // 触发器：手机状态、消息通知、定时，模型能看、能建、能改、能删。
      ..register(TriggerListTool(triggers))
      ..register(TriggerSaveTool(triggers))
      ..register(TriggerDeleteTool(triggers));
    if (isDesktopPlatform) {
      registry.register(LocalExecTool());
    }
    // Advance Master 才拿得到「加主机 / 删主机」这两个写口子。
    if (c.advanceMaster) {
      registry.register(AddHostTool(hosts: hosts, secrets: secrets, pool: pool));
      registry.register(RemoveHostTool(hosts: hosts, secrets: secrets));
    }
    final AgentLoop loop = AgentLoop(
      llm: SettingsLlmProvider(settings, secrets, profileId: () => c.profileId),
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
    final AgentSession session = AgentSession(loop: loop, memory: store);
    syncTools(session);
    return session;
  }

  /// Rebuild the transcript on disk. Called after every turn.
  Future<void> persist(Conversation c) => conversations.save(c);
}

/// 这个对话该用哪份系统提示词：对话自己的优先，然后是设置里的，都没有就用内置那份。
String promptFor(SettingsStore settings, Conversation c) {
  final String own = c.systemPrompt.trim();
  if (own.isNotEmpty) return own;
  final ModelProfile profile = profileOf(settings.value, c.profileId);
  final String byProfile = profile.userPrompt.trim();
  if (byProfile.isNotEmpty) return byProfile;
  final String bound = profile.prompt.trim();
  if (bound.isNotEmpty) return bound;
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
      '  写、列、读、删文件用 temp_file；传给主机用 temp_upload，从主机拉回来用 temp_download。');
  b.writeln(
      '- 一条命令能问完的别拆成几次；输出先筛再取（-q、--no-legend、awk 只留要的列），别把整张表刷进来。');
  b.writeln(
      '- 同一件事这一场里确认过就不再复核，除非有理由怀疑它变了。');
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
