import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/hosts.dart';
import 'data/update.dart';
import 'services.dart';
import 'ui/about_page.dart';
import 'ui/chat_page.dart';
import 'ui/hosts_page.dart';
import 'ui/memory_page.dart';
import 'ui/settings_page.dart';
import 'ui/terminal_page.dart';
import 'ui/theme.dart';
import 'version.dart';

class CarbideApp extends StatelessWidget {
  const CarbideApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Carbide Shell',
      debugShowCheckedModeBanner: false,
      theme: C.theme(),
      home: HomeShell(services: services),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.services});

  final AppServices services;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeCheckUpdate());
  }

  /// Once a day, ask GitHub whether there is a newer release. Offline is fine:
  /// a failed check says nothing and is tried again tomorrow.
  Future<void> _maybeCheckUpdate() async {
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
              child: const Text('去下载', style: TextStyle(fontSize: 13, color: C.ink)),
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

  @override
  Widget build(BuildContext context) {
    final AppServices s = widget.services;
    final List<HostEntry> hosts = s.hosts.hosts;
    final String title = hosts.isEmpty ? '没有主机' : hosts.first.name;
    final String address = hosts.isEmpty ? '先在主机页加一台' : hosts.first.address;

    return Scaffold(
      body: SafeArea(
        child: IndexedStack(
          index: _index,
          children: <Widget>[
            ChatPage(
              agent: s.agent,
              title: title,
              address: address,
              hostCount: hosts.length,
              onOpenHosts: () => setState(() => _index = 1),
            ),
            HostsPage(hosts: s.hosts, secrets: s.secrets, onChanged: _refresh),
            TerminalPage(hosts: s.hosts, pool: s.pool),
            MemoryPage(memory: s.memory, onChanged: _refresh),
            SettingsPage(
              settings: s.settings,
              secrets: s.secrets,
              policy: s.policy,
              agent: s.agent,
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
            _nav(1, Icons.dns_outlined, '主机'),
            _nav(2, Icons.terminal, '终端'),
            _nav(3, Icons.bookmarks_outlined, '记忆'),
            _nav(4, Icons.settings_outlined, '设置'),
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
        onTap: () => setState(() => _index = index),
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
