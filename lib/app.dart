import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/conversation.dart';
import 'data/foreground.dart';
import 'data/hosts.dart';
import 'data/hub.dart';
import 'data/notice_reply.dart';
import 'data/tasks.dart';
import 'data/temp_files.dart';
import 'data/triggers.dart';
import 'data/update.dart';
import 'services.dart';
import 'ui/about_page.dart';
import 'ui/chat_page.dart';
import 'ui/components.dart';
import 'ui/conversation_actions.dart';
import 'ui/conversation_rail.dart';
import 'ui/conversations_page.dart';
import 'ui/env_page.dart';
import 'ui/hosts_page.dart';
import 'ui/memory_page.dart';
import 'ui/motion.dart';
import 'ui/pet.dart';
import 'ui/settings_page.dart';
import 'ui/tasks_page.dart';
import 'ui/temp_files_page.dart';
import 'ui/usage_page.dart';
import 'ui/terminal_page.dart';
import 'ui/theme.dart';
import 'ui/triggers_page.dart';

class CarbideApp extends StatelessWidget {
  const CarbideApp({
    super.key,
    required this.services,
    required this.hub,
    required this.scheduler,
    required this.triggers,
    required this.replies,
  });

  final AppServices services;
  final SessionHub hub;
  final TaskScheduler scheduler;

  /// 触发器：手机状态、消息通知、定时。
  final TriggerRunner triggers;

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
        triggers: triggers,
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
    required this.triggers,
    required this.replies,
  });

  final AppServices services;
  final SessionHub hub;
  final TaskScheduler scheduler;
  final TriggerRunner triggers;
  final NoticeReply replies;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final GlobalKey<ScaffoldState> _scaffold = GlobalKey<ScaffoldState>();
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

  void _openEnv() {
    final AppServices s = widget.services;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EnvPage(env: s.env),
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

    return PopScope(
      canPop: _atRoot,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        _back();
      },
      child: Scaffold(
          key: _scaffold,
          // 窄屏时会话侧边栏从左边滑出来，和宽屏那一栏是同一份。
          drawer: _index == 0 ? _sidebar() : null,
          body: MediaQuery.removePadding(
          context: context,
          // 底部的系统条距离由下面那条导航条让，页面里不再重复让一次。
          removeBottom: true,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext ctx, BoxConstraints box) {
                // 宽屏把会话挪到左边一栏：侧边栏选对话，右边一直是正文。
                final bool rail = box.maxWidth >= 900;
                return IndexedStack(
                  index: _index,
                  children: <Widget>[
                    rail ? _railTab(s) : _listTab(s),
                    TasksPage(
                      tasks: s.tasks,
                      watches: s.watches,
                      scheduler: widget.scheduler,
                      hosts: s.hosts,
                      triggers: s.triggers,
                      triggerRunner: widget.triggers,
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
                      onOpenEnv: _openEnv,
                      filesSummary: _filesSummary(),
                      envSummary: widget.services.env.all.isEmpty
                          ? '还没存'
                          : '${widget.services.env.all.length} 把',
                      usage: s.usage,
                      mail: s.mail,
                    ),
                  ],
                );
              },
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

  /// 窄屏：会话列表是一整页，点进去就是那一场对话。
  Widget _listTab(AppServices s) {
    final Conversation? open = _open;
    return AnimatedSwitcher(
      duration: Motion.swap,
      switchInCurve: Motion.curve,
      child: open == null
          ? KeyedSubtree(
              key: const ValueKey<String>('threads'),
              child: ConversationsPage(
                services: s,
                hub: widget.hub,
                onOpen: (Conversation c) => setState(() => _open = c),
                onChanged: _refresh,
              ),
            )
          : _chat(s, open, wide: false),
    );
  }

  /// 宽屏：左边一栏会话，右边是选中的那一场。
  Widget _railTab(AppServices s) {
    final Conversation? open = _open;
    return Row(
      children: <Widget>[
        ConversationRail(
          services: s,
          hub: widget.hub,
          currentId: open?.id ?? '',
          onOpen: (Conversation c) => setState(() => _open = c),
          onNew: _newConversation,
          onDelete: _deleteConversation,
        ),
        const VerticalDivider(width: 1, thickness: 1, color: C.rule),
        Expanded(
          child: AnimatedSwitcher(
            duration: Motion.swap,
            switchInCurve: Motion.curve,
            child: open == null ? _noOpen() : _chat(s, open),
          ),
        ),
      ],
    );
  }

  Widget _chat(AppServices s, Conversation open, {bool wide = true}) {
    return ChatPage(
      key: ValueKey<String>(open.id),
      services: s,
      hub: widget.hub,
      conversation: open,
      subtitle: _subtitle(open),
      onBack: () {
        setState(() => _open = null);
        _refresh();
      },
      onOpenSidebar: wide ? null : () => _scaffold.currentState?.openDrawer(),
    );
  }

  /// 窄屏的侧边栏：和宽屏那一栏同一份，选完自动收起来。
  Widget _sidebar() {
    final AppServices s = widget.services;
    return Drawer(
      width: ConversationRail.width,
      backgroundColor: C.paper,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: ConversationRail(
          services: s,
          hub: widget.hub,
          currentId: _open?.id ?? '',
          onOpen: (Conversation c) {
            _scaffold.currentState?.closeDrawer();
            setState(() => _open = c);
          },
          onNew: () async {
            _scaffold.currentState?.closeDrawer();
            await _newConversation();
          },
          onDelete: _deleteConversation,
        ),
      ),
    );
  }

  /// 宽屏还没选对话时右边那一块：说一句，给一个开新对话的按钮。
  Widget _noOpen() {
    return Container(
      key: const ValueKey<String>('none'),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PetAvatar(
            size: 150,
            mood: petMoodNow(
              running: widget.hub.runningCount > 0,
              waiting: widget.hub.waitingOnes.isNotEmpty,
            ),
            showState: true,
          ),
          const SizedBox(height: 16),
          const Text('左边选一个对话',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          const Text('也可以新开一个，指定它管哪台主机。',
              style: TextStyle(fontSize: 12.5, color: C.grey, height: 1.6)),
          const SizedBox(height: 18),
          SquareButton(label: '新对话', filled: true, onPressed: _newConversation),
        ],
      ),
    );
  }

  Future<void> _newConversation() async {
    final Conversation? c = await newConversationDialog(context, widget.services);
    if (c == null || !mounted) return;
    setState(() => _open = c);
    _refresh();
  }

  Future<void> _deleteConversation(Conversation c) async {
    final bool ok = await confirmDeleteConversation(context, c);
    if (!ok) return;
    await widget.services.conversations.remove(c.id);
    widget.hub.forget(c.id);
    if (!mounted) return;
    setState(() {
      if (_open?.id == c.id) _open = null;
    });
    _refresh();
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
