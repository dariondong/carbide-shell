import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/conversation.dart';
import 'data/foreground.dart';
import 'data/hosts.dart';
import 'data/hub.dart';
import 'data/notice_reply.dart';
import 'data/tasks.dart';
import 'data/temp_files.dart';
import 'data/update.dart';
import 'services.dart';
import 'ui/about_page.dart';
import 'ui/chat_page.dart';
import 'ui/conversations_page.dart';
import 'ui/hosts_page.dart';
import 'ui/memory_page.dart';
import 'ui/settings_page.dart';
import 'ui/tasks_page.dart';
import 'ui/temp_files_page.dart';
import 'ui/usage_page.dart';
import 'ui/terminal_page.dart';
import 'ui/theme.dart';

class CarbideApp extends StatelessWidget {
  const CarbideApp({
    super.key,
    required this.services,
    required this.hub,
    required this.scheduler,
    required this.replies,
  });

  final AppServices services;
  final SessionHub hub;
  final TaskScheduler scheduler;

  /// 通知里回的那句话往哪儿送。
  final NoticeReply replies;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carbide Shell',
      debugShowCheckedModeBanner: false,
      theme: C.theme(),
      home: HomeShell(
        services: services,
        hub: hub,
        scheduler: scheduler,
        replies: replies,
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.services,
    required this.hub,
    required this.scheduler,
    required this.replies,
  });

  final AppServices services;
  final SessionHub hub;
  final TaskScheduler scheduler;
  final NoticeReply replies;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  Conversation? _open;

  @override
  void initState() {
    super.initState();
    widget.scheduler.onChanged = _refresh;
    widget.scheduler.start();
    // 有几个对话在跑、在等确认，列表要跟着变；正文的增量不重画整个外壳。
    widget.hub.addListener(_onHub);
    // 通知上那颗回复：字到了就往对话里送。
    ForegroundTask.listen(_onReply);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCheckUpdate());
  }

  @override
  void dispose() {
    widget.scheduler.stop();
    widget.hub.removeListener(_onHub);
    ForegroundTask.listen(null);
    super.dispose();
  }

  /// 通知里写的那句：交给它去发，然后把那个对话摆到眼前。
  Future<void> _onReply(String text) async {
    final String id = await widget.replies.deliver(text);
    if (!mounted || id.isEmpty) return;
    if (_open?.id == id) return;
    final Conversation? c = widget.services.conversations.byId(id);
    if (c == null) return;
    setState(() => _open = c);
  }

  /// Once a day, ask GitHub for a newer release. Offline is fine: a failed
  /// check says nothing and is retried tomorrow.
  Future<void> _maybeCheckUpdate() async {
    if (!widget.services.settings.value.autoCheckUpdate) return;
    final DateTime? last = DateTime.tryParse(widget.services.settings.value.lastUpdateCheck);
    if (last != null && DateTime.now().difference(last) < const Duration(hours: 24)) return;
    final UpdateChecker checker = UpdateChecker();
    try {
      final List<UpdateInfo> list = await checker.fetch();
      widget.services.settings.value.lastUpdateCheck = DateTime.now().toIso8601String();
      await widget.services.settings.save();
      if (list.isEmpty || !mounted) return;
      UpdateInfo best = list.first;
      for (final UpdateInfo i in list) {
        if (compareVersions(i.version, best.version) > 0) best = i;
      }
      if (!best.newerThanCurrent || !mounted) return;
      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text('有新版本 ${best.version}'),
          content: SingleChildScrollView(
            child: Text(shortNotes(best.notes),
                style: const TextStyle(fontSize: 13, height: 1.6)),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('以后再说', style: TextStyle(fontSize: 13, color: C.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                final String url = best.apkUrl.isEmpty ? best.pageUrl : best.apkUrl;
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
              },
              child: const Text('去下载', style: TextStyle(fontSize: 13, color: C.blue)),
            ),
          ],
        ),
      );
    } catch (_) {
      // 离线、限流都当作没发生。
    } finally {
      checker.close();
    }
  }

  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          backgroundColor: C.paper,
          body: SafeArea(
            child: AboutPage(
              hostCount: widget.services.hosts.hosts.length,
              conversationCount: widget.services.conversations.all.length,
              usage: widget.services.usage,
            ),
          ),
        ),
      ),
    );
  }

  void _openUsage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UsagePage(usage: widget.services.usage),
      ),
    );
  }

  void _openFiles() {
    final AppServices s = widget.services;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TempFilesPage(files: s.files, hosts: s.hosts, pool: s.pool),
      ),
    );
  }

  /// 设置页那一行右边写文件区的轻重，读一眼目录就够。
  String _filesSummary() {
    try {
      final List<TempFile> all = widget.services.files.list();
      if (all.isEmpty) return '空的';
      int sum = 0;
      for (final TempFile f in all) {
        sum += f.size;
      }
      return '${all.length} 个 · ${tempSize(sum)}';
    } catch (_) {
      return '';
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// 已经在最外面：会话列表、第一个页签。
  bool get _atRoot => _index == 0 && _open == null;

  /// 返回键先退一层：对话→列表，其它页签→会话，都退完了才交给系统退出。
  void _back() {
    if (_open != null) {
      setState(() => _open = null);
      return;
    }
    if (_index != 0) setState(() => _index = 0);
  }

  String _busy = '';

  /// 只在「谁在跑、谁在等」变了的时候重画外壳。
  void _onHub() {
    final String now = widget.hub.signature;
    if (now == _busy) return;
    _busy = now;
    _refresh();
  }

  String _subtitle(Conversation c) {
    if (c.advanceMaster) return 'Advance Master · 全部主机';
    if (c.multiHost) return '全部主机';
    final HostEntry? h = widget.services.hosts.byId(c.hostId);
    return h == null ? '主机已删除' : '${h.name} · ${h.address}';
  }

  @override
  Widget build(BuildContext context) {
    final AppServices s = widget.services;
    final Conversation? open = _open;

    final Widget chatTab = open == null
        ? ConversationsPage(
            services: s,
            hub: widget.hub,
            onOpen: (Conversation c) => setState(() => _open = c),
            onChanged: _refresh,
          )
        : ChatPage(
            key: ValueKey<String>(open.id),
            services: s,
            hub: widget.hub,
            conversation: open,
            subtitle: _subtitle(open),
            onBack: () {
              setState(() => _open = null);
              _refresh();
            },
          );

    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _back();
      },
      child: Scaffold(
          body: MediaQuery.removePadding(
          context: context,
          // 底部的系统栏距离由下面那条导航条让，页面里不再重复让一次。
          removeBottom: true,
          child: SafeArea(
            child: IndexedStack(
              index: _index,
              children: <Widget>[
                chatTab,
                TasksPage(
                  tasks: s.tasks,
                  watches: s.watches,
                  scheduler: widget.scheduler,
                  hosts: s.hosts,
                  onChanged: _refresh,
                ),
                HostsPage(
                  hosts: s.hosts,
                  secrets: s.secrets,
                  pool: s.pool,
                  onChanged: _refresh,
                ),
                TerminalPage(hosts: s.hosts, pool: s.pool),
                MemoryPage(services: s, onChanged: _refresh),
                SettingsPage(
                  settings: s.settings,
                  secrets: s.secrets,
                  policy: s.policy,
                  conversations: s.conversations.all,
                  onConversationChanged: (Conversation c) => s.conversations.save(c),
                  onOpenAbout: _openAbout,
                  onOpenUsage: _openUsage,
                  onOpenFiles: _openFiles,
                  filesSummary: _filesSummary(),
                  usage: s.usage,
                  mail: s.mail,
                ),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: C.card,
            border: Border(top: BorderSide(color: C.rule)),
          ),
          // 三键导航条、手势条的高度加在这条底下，按钮不会被盖住。
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 60,
              child: Row(
                children: <Widget>[
                  _nav(0, Icons.forum_outlined, '会话'),
                  _nav(1, Icons.schedule_outlined, '任务'),
                  _nav(2, Icons.dns_outlined, '主机'),
                  _nav(3, Icons.terminal, '终端'),
                  _nav(4, Icons.bookmarks_outlined, '记忆'),
                  _nav(5, Icons.settings_outlined, '设置'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _nav(int index, IconData icon, String label) {
    final bool on = _index == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          // 正在某个页签上再点一下：对话退回列表，别的页签原地不动。
          if (index == _index && index == 0 && _open != null) {
            _open = null;
            return;
          }
          _index = index;
        }),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: on ? C.blueSoft : const Color(0x00000000),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 19, color: on ? C.blue : C.grey2),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: on ? C.blue : C.grey,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
