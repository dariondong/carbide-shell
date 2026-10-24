import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';

import '../data/hosts.dart';
import '../tools/ssh_tools.dart';
import 'components.dart';
import 'theme.dart';

/// A real shell on a saved host. Input goes straight to the pty.
class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key, required this.hosts, required this.pool});

  final HostStore hosts;
  final SshPool pool;

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final StringBuffer _buffer = StringBuffer();
  HostEntry? _host;
  SSHSession? _session;
  bool _connecting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    final List<HostEntry> list = widget.hosts.hosts;
    if (list.isNotEmpty) _host = list.first;
  }

  @override
  void dispose() {
    _session?.close();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _write(String text) {
    if (text.isEmpty) return;
    setState(() {
      _buffer.write(text);
      if (_buffer.length > 40000) {
        final String all = _buffer.toString();
        _buffer
          ..clear()
          ..write(all.substring(all.length - 40000));
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
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
        _write(utf8.decode(data, allowMalformed: true));
      });
      session.stderr.listen((Uint8List data) {
        _write(utf8.decode(data, allowMalformed: true));
      });
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

  void _submit() {
    final String text = _input.text;
    _input.clear();
    final SSHSession? session = _session;
    if (session == null) return;
    session.write(Uint8List.fromList(utf8.encode('$text\n')));
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
            border: Border(bottom: BorderSide(color: C.ink)),
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
                      onChanged: live
                          ? null
                          : (HostEntry? h) => setState(() => _host = h),
                    ),
                  ),
                ),
              Text(live ? '已连接' : (_connecting ? '连接中' : '未连接'),
                  style: C.monoSmall.copyWith(color: live ? C.blue : C.grey)),
              const SizedBox(width: 12),
              if (live)
                GestureDetector(
                  onTap: _disconnect,
                  child: const Text('断开', style: TextStyle(fontSize: 12, color: C.grey)),
                )
              else
                SquareButton(
                  label: '连接',
                  onPressed: list.isEmpty ? null : _connect,
                ),
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
            color: C.ink,
            width: double.infinity,
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _buffer.isEmpty ? '连上之后这里就是它的 shell。' : _buffer.toString(),
                style: const TextStyle(
                  fontFamily: C.monoFamily,
                  fontSize: 12.5,
                  height: 1.6,
                  color: C.onInk,
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Row(
            children: <Widget>[
              Text('❯', style: C.mono.copyWith(color: live ? C.blue : C.grey2)),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: live,
                  style: const TextStyle(fontFamily: C.monoFamily, fontSize: 13),
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(hintText: '输入命令，回车发送'),
                ),
              ),
              GestureDetector(
                onTap: live ? _submit : null,
                child: Container(
                  width: 28,
                  height: 28,
                  color: live ? C.ink : C.rule2,
                  alignment: Alignment.center,
                  child: const Icon(Icons.arrow_forward, size: 15, color: C.paper),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
