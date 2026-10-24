import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/conversation.dart';
import 'data/hosts.dart';
import 'data/tasks.dart';
import 'data/update.dart';
import 'services.dart';
import 'ui/about_page.dart';
import 'ui/chat_page.dart';
import 'ui/conversations_page.dart';
import 'ui/hosts_page.dart';
import 'ui/memory_page.dart';
import 'ui/settings_page.dart';
import 'ui/tasks_page.dart';
import 'ui/terminal_page.dart';
import 'ui/theme.dart';

class CarbideApp extends StatelessWidget {
  const CarbideApp({
    super.key,
    required this.services,
    required this.tasks,
    required this.scheduler,
  });

  final AppServices services;
  final TaskStore tasks;
  final TaskScheduler scheduler;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carbide Shell',
      debugShowCheckedModeBanner: false,
      theme: C.theme(),
      home: HomeShell(services: services, tasks: tasks, scheduler: scheduler),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.services,
    required this.tasks,
    required this.scheduler,
  });

  final AppServices services;
  final TaskStore tasks;
  final TaskScheduler scheduler;

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCheckUpdate());
  }

  @override
  void dispose() {
    widget.scheduler.stop();
    super.dispose();
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
        builder: (_) => const Scaffold(backgroundColor: C.paper, body: SafeArea(child: AboutPage())),
      ),
    );
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  String _subtitle(Conversation c) {
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
            onOpen: (Conversation c) => setState(() => _open = c),
            onChanged: _refresh,
          )
        : ChatPage(
            key: ValueKey<String>(open.id),
            services: s,
            conversation: open,
            subtitle: _subtitle(open),
            onBack: () {
              setState(() => _open = null);
              _refresh();
            },
          );

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: <Widget>[
            chatTab,
            TasksPage(
              tasks: widget.tasks,
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
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: 60,
        decoration: const BoxDecoration(
          color: C.card,
          border: Border(top: BorderSide(color: C.rule)),
        ),
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
    );
  }

  Widget _nav(int index, IconData icon, String label) {
    final bool on = _index == index;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _index = index;
          if (index != 0) _open = _open;
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
