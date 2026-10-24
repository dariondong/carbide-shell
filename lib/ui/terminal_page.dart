import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../data/hosts.dart';
import '../tools/ssh_tools.dart';
import 'components.dart';
import 'theme.dart';

/// The terminal theme: our ink as the background, our blue as the cursor.
const TerminalTheme _termTheme = TerminalTheme(
  cursor: Color(0xFF8FB0FF),
  selection: Color(0x558FB0FF),
  foreground: Color(0xFFE9E7E1),
  background: Color(0xFF111315),
  black: Color(0xFF111315),
  red: Color(0xFFE0574C),
  green: Color(0xFF57C785),
  yellow: Color(0xFFE0A24C),
  blue: Color(0xFF7FA0FF),
  magenta: Color(0xFFC77DFF),
  cyan: Color(0xFF4FD3C4),
  white: Color(0xFFE9E7E1),
  brightBlack: Color(0xFF7B838A),
  brightRed: Color(0xFFFF7B70),
  brightGreen: Color(0xFF7BE39B),
  brightYellow: Color(0xFFFFC46B),
  brightBlue: Color(0xFF9DBBFF),
  brightMagenta: Color(0xFFDD9BFF),
  brightCyan: Color(0xFF6EE7DA),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0xFFFFF2B0),
  searchHitBackgroundCurrent: Color(0xFFB9FF9E),
  searchHitForeground: Color(0xFF111315),
);

/// A real shell on a saved host. xterm does the ANSI, the pty does the rest.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.hosts, required this.pool});

  final HostStore hosts;
  final SshPool pool;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final Terminal _terminal = Terminal(maxLines: 5000);
  HostEntry? _host;
  SSHSession? _session;
  bool _connecting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final List<HostEntry> list = widget.hosts.hosts;
    if (list.isNotEmpty) _host = list.first;
    _terminal.onOutput = (String data) {
      _session?.write(Uint8List.fromList(utf8.encode(data)));
    };
    _terminal.onResize = (int width, int height, int pixelWidth, int pixelHeight) {
      _session?.resizeTerminal(width, height, pixelWidth, pixelHeight);
    };
  }

  @override
  void dispose() {
    _session?.close();
    super.dispose();
  }

  Future<void> _connect() async {
    final HostEntry? host = _host;
    if (host == null || _connecting) return;
    setState(() {
      _connecting = true;
      _error = '';
    });
    try {
      final SSHClient client = await widget.pool.connect(host);
      final SSHSession session = await client.shell();
      session.stdout.listen((Uint8List data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });
      session.stderr.listen((Uint8List data) {
        _terminal.write(utf8.decode(data, allowMalformed: true));
      });
      session.done.then((_) {
        if (mounted && _session == session) {
          setState(() => _session = null);
        }
      });
      session.resizeTerminal(_terminal.viewWidth, _terminal.viewHeight);
      setState(() => _session = session);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _disconnect() async {
    _session?.close();
    setState(() => _session = null);
    if (_host != null) await widget.pool.drop(_host!.id);
  }

  @override
  Widget build(BuildContext context) {
    final List<HostEntry> list = widget.hosts.hosts;
    final bool live = _session != null;
    return Column(
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
          ),
          child: Row(
            children: <Widget>[
              const Text('终端', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 12),
              if (list.isEmpty)
                Expanded(child: Text('没有主机', style: C.monoSmall))
              else
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<HostEntry>(
                      value: _host,
                      isDense: true,
                      style: C.monoSmall.copyWith(color: C.ink, fontSize: 12),
                      items: list
                          .map((HostEntry h) => DropdownMenuItem<HostEntry>(
                                value: h,
                                child: Text(h.name, style: C.monoSmall.copyWith(color: C.ink)),
                              ))
                          .toList(),
                      onChanged:
                          live ? null : (HostEntry? h) => setState(() => _host = h),
                    ),
                  ),
                ),
              Text(
                live ? '已连接' : (_connecting ? '连接中' : '未连接'),
                style: C.monoSmall.copyWith(color: live ? C.blue : C.grey),
              ),
              const SizedBox(width: 12),
              if (live)
                GestureDetector(
                  onTap: _disconnect,
                  child: const Text('断开', style: TextStyle(fontSize: 12, color: C.grey)),
                )
              else
                SquareButton(label: '连接', onPressed: list.isEmpty ? null : _connect),
            ],
          ),
        ),
        if (_error.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: C.paper2,
            child: Text(_error, style: C.monoSmall.copyWith(color: C.ink)),
          ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: C.termBg,
              borderRadius: BorderRadius.circular(C.radius),
            ),
            width: double.infinity,
            child: TerminalView(
              _terminal,
              theme: _termTheme,
              textStyle: const TerminalStyle(fontSize: 12.5, height: 1.35),
              padding: const EdgeInsets.all(12),
              backgroundOpacity: 1,
              autofocus: true,
              keyboardType: TextInputType.text,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: <Widget>[
              Text(
                live ? '直接在上面打字，回车发送' : '连上之后这里就是它的 shell',
                style: const TextStyle(fontSize: 11, color: C.grey),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _terminal.eraseDisplay(),
                child: const Text('清屏', style: TextStyle(fontSize: 11, color: C.grey)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
