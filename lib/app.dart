import 'package:flutter/material.dart';

import 'data/hosts.dart';
import 'services.dart';
import 'ui/chat_page.dart';
import 'ui/hosts_page.dart';
import 'ui/settings_page.dart';
import 'ui/terminal_page.dart';
import 'ui/theme.dart';

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
            SettingsPage(
              settings: s.settings,
              secrets: s.secrets,
              policy: s.policy,
              agent: s.agent,
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        height: 58,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: C.rule)),
        ),
        child: Row(
          children: <Widget>[
            _nav(0, Icons.forum_outlined, '会话'),
            _nav(1, Icons.dns_outlined, '主机'),
            _nav(2, Icons.terminal, '终端'),
            _nav(3, Icons.settings_outlined, '设置'),
          ],
        ),
      ),
    );
  }

  Widget _nav(int index, IconData icon, String label) {
    final bool on = _index == index;
    final Color color = on ? C.ink : C.grey;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _index = index),
        child: Column(
          children: <Widget>[
            Container(height: 2, color: on ? C.ink : const Color(0x00000000)),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, size: 18, color: color),
                  const SizedBox(height: 4),
                  Text(label, style: TextStyle(fontSize: 10.5, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
