import 'dart:async';

import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/llm_base.dart';
import '../core/models.dart';
import 'components.dart';
import 'theme.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.agent,
    required this.title,
    required this.address,
    required this.hostCount,
    required this.onOpenHosts,
  });

  final AgentLoop agent;
  final String title;
  final String address;
  final int hostCount;
  final VoidCallback onOpenHosts;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> implements Approver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  ApprovalRequest? _pending;
  Completer<bool>? _waiter;
  CancelToken? _cancel;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    widget.agent.approver = this;
    widget.agent.onChanged = _refresh;
  }

  @override
  void dispose() {
    widget.agent.onChanged = null;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Future<bool> confirm(ApprovalRequest request) {
    final Completer<bool> waiter = Completer<bool>();
    setState(() {
      _pending = request;
      _waiter = waiter;
    });
    return waiter.future;
  }

  void _decide(bool allowed) {
    final Completer<bool>? waiter = _waiter;
    setState(() {
      _pending = null;
      _waiter = null;
    });
    if (waiter != null && !waiter.isCompleted) waiter.complete(allowed);
  }

  Future<void> _send() async {
    final String text = _input.text.trim();
    if (text.isEmpty || _running) return;
    _input.clear();
    setState(() => _running = true);
    final CancelToken token = CancelToken();
    _cancel = token;
    try {
      await widget.agent.send(text, cancel: token);
    } finally {
      if (mounted) {
        setState(() => _running = false);
      }
    }
  }

  void _stop() {
    _cancel?.cancel();
    _decide(false);
  }

  String? _outputFor(String id) {
    for (final LlmMessage m in widget.agent.history) {
      if (m.role == LlmRole.tool && m.toolCallId == id) return m.text;
    }
    return null;
  }

  List<Widget> _thread() {
    final List<Widget> out = <Widget>[];
    for (final LlmMessage m in widget.agent.history) {
      if (m.role == LlmRole.user) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('❯', style: TextStyle(fontSize: 15, color: C.blue, height: 1.6)),
              const SizedBox(width: 10),
              Expanded(child: Text(m.text, style: C.ask)),
            ],
          ),
        ));
      } else if (m.role == LlmRole.assistant) {
        if (m.text.trim().isNotEmpty) {
          out.add(Padding(
            padding: const EdgeInsets.only(bottom: 18, left: 24),
            child: Text(m.text, style: C.answer),
          ));
        }
        for (final LlmToolCall call in m.calls) {
          out.add(Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ToolCallCard(
              call: call,
              output: _outputFor(call.id),
              running: _running && _outputFor(call.id) == null,
            ),
          ));
        }
      }
    }
    if (out.isEmpty) {
      out.add(_empty());
    }
    return out;
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(widget.hostCount == 0 ? '还没有主机' : '说说要做什么',
              style: const TextStyle(fontSize: 18, color: C.ink, height: 1.4)),
          const SizedBox(height: 10),
          Text(
            widget.hostCount == 0
                ? '先去主机那一页加一台，密钥只留在本机。'
                : '比如：看看 web-01 的磁盘，把 nginx 的老日志清掉。',
            style: C.answer,
          ),
          if (widget.hostCount == 0) ...<Widget>[
            const SizedBox(height: 20),
            SquareButton(label: '去加主机', filled: true, onPressed: widget.onOpenHosts),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.address, style: C.monoSmall, overflow: TextOverflow.ellipsis),
              ),
              Text('${widget.agent.step}/${widget.agent.maxSteps}', style: C.monoSmall),
              const SizedBox(width: 12),
              if (_running)
                GestureDetector(
                  onTap: _stop,
                  child: Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.card,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: C.rule2),
                    ),
                    child: Container(width: 9, height: 9, color: C.body),
                  ),
                )
              else
                const SizedBox(width: 26),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _thread(),
            ),
          ),
        ),
        if (_pending != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ApprovalCard(request: _pending!, onDecide: _decide),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(C.radius),
              border: Border.all(color: C.rule),
              boxShadow: C.softShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                const Text('❯', style: TextStyle(fontSize: 14, color: C.blue)),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_running,
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: '接着说，或者让它停'),
                  ),
                ),
                GestureDetector(
                  onTap: _running ? null : _send,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _running ? C.rule2 : C.blue,
                      borderRadius: BorderRadius.circular(C.radiusSmall),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.arrow_upward, size: 18, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
