import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/conversation.dart';
import '../core/llm_base.dart';
import '../core/models.dart';
import '../services.dart';
import 'components.dart';
import 'theme.dart';

/// One conversation. Its transcript lives on disk, so leaving and coming back
/// keeps everything.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.services,
    required this.conversation,
    required this.subtitle,
    required this.onBack,
  });

  final AppServices services;
  final Conversation conversation;
  final String subtitle;
  final VoidCallback onBack;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> implements Approver {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  AgentSession? _session;
  ApprovalRequest? _pending;
  String _kind = '';
  Completer<bool>? _waiter;
  CancelToken? _cancel;
  bool _running = false;
  final List<String> _images = <String>[];
  final List<String> _attachNames = <String>[];

  List<LlmMessage> get _messages => widget.conversation.messages;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  Future<void> _attach() async {
    final AgentSession session = await widget.services.sessionFor(widget.conversation);
    session.loop.approver = this;
    session.loop.onChanged = _refresh;
    if (!mounted) return;
    setState(() => _session = session);
  }

  @override
  void dispose() {
    _session?.loop.onChanged = null;
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Future<bool> confirm(ApprovalRequest request) async {
    final String kind = approvalKind(request.call);
    if (widget.conversation.allowsKind(kind)) return true;
    final Completer<bool> waiter = Completer<bool>();
    setState(() {
      _pending = request;
      _kind = kind;
      _waiter = waiter;
    });
    return waiter.future;
  }

  Future<void> _allowKind() async {
    final String kind = _kind;
    if (kind.isNotEmpty && !widget.conversation.kindApprovals.contains(kind)) {
      widget.conversation.kindApprovals.add(kind);
      await widget.services.persist(widget.conversation);
    }
    _decide(true);
  }

  Future<void> _allowAll() async {
    widget.conversation.autoApproveAll = true;
    await widget.services.persist(widget.conversation);
    _decide(true);
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
    final AgentSession? session = _session;
    final String text = _input.text.trim();
    if (session == null || text.isEmpty || _running) return;
    _input.clear();
    setState(() => _running = true);
    final CancelToken token = CancelToken();
    _cancel = token;
    try {
      session.loop.maxSteps = widget.services.settings.value.maxSteps;
      final List<String> images = List<String>.of(_images);
      _images.clear();
      _attachNames.clear();
      await session.loop.send(text, cancel: token, images: images);
      await widget.services.persist(widget.conversation);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _pickFiles() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    for (final PlatformFile f in picked.files) {
      final List<int>? bytes = f.bytes;
      if (bytes == null) continue;
      final String name = f.name.toLowerCase();
      final bool isImage = name.endsWith('.png') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg') ||
          name.endsWith('.gif') ||
          name.endsWith('.webp') ||
          name.endsWith('.bmp');
      if (isImage) {
        if (bytes.length > 3 * 1024 * 1024) {
          _toast('${f.name} 太大了，图片请小于 3 MB。');
          continue;
        }
        final String mime = name.endsWith('.png')
            ? 'image/png'
            : name.endsWith('.webp')
                ? 'image/webp'
                : name.endsWith('.gif')
                    ? 'image/gif'
                    : 'image/jpeg';
        _images.add('data:$mime;base64,${base64Encode(bytes)}');
        _attachNames.add(f.name);
        continue;
      }
      final bool isText = name.endsWith('.txt') ||
          name.endsWith('.md') ||
          name.endsWith('.json') ||
          name.endsWith('.csv') ||
          name.endsWith('.log') ||
          name.endsWith('.yaml') ||
          name.endsWith('.yml') ||
          name.endsWith('.conf') ||
          name.endsWith('.ini') ||
          name.endsWith('.sh');
      if (isText) {
        final String body = utf8.decode(bytes, allowMalformed: true);
        if (body.length > 60000) {
          _toast('${f.name} 太长了，先截前 60000 字。');
        }
        final String clipped = body.length > 60000 ? body.substring(0, 60000) : body;
        _input.text = '${_input.text}${_input.text.isEmpty ? '' : '\n\n'}'
            '文件 ${f.name}：\n\n```\n$clipped\n```';
        _attachNames.add(f.name);
        continue;
      }
      _toast('${f.name} 的类型还读不了，现在支持图片和纯文本。');
    }
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _stop() {
    _cancel?.cancel();
    _decide(false);
  }

  Map<String, String> _outputs() {
    final Map<String, String> out = <String, String>{};
    for (final LlmMessage m in _messages) {
      if (m.role == LlmRole.tool) out[m.toolCallId] = m.text;
    }
    return out;
  }

  String _runningId() {
    if (!_running) return '';
    for (final LlmMessage m in _messages) {
      if (m.role != LlmRole.assistant) continue;
      for (final LlmToolCall c in m.calls) {
        if (!_outputs().containsKey(c.id)) return c.id;
      }
    }
    return '';
  }

  List<Widget> _thread() {
    final List<Widget> out = <Widget>[];
    final Map<String, String> outputs = _outputs();
    final String runningId = _runningId();
    for (final LlmMessage m in _messages) {
      if (m.role == LlmRole.user) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 14, top: 4),
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
            padding: const EdgeInsets.only(bottom: 12, left: 22),
            child: Text(m.text, style: C.answer),
          ));
        }
        if (m.calls.isNotEmpty) {
          out.add(Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: ToolRunGroup(
              calls: m.calls,
              outputs: outputs,
              runningId: runningId,
            ),
          ));
        }
      }
    }
    final String partial = _session?.loop.partial ?? '';
    if (partial.isNotEmpty) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 22),
        child: Text(partial, style: C.answer),
      ));
    }
    if (out.isEmpty) out.add(_empty());
    return out;
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('说说要做什么',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          const Text('比如：看看磁盘，把 nginx 的老日志清一下。', style: C.answer),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: C.paper2,
              borderRadius: BorderRadius.circular(C.radiusSmall),
            ),
            child: Text(
              widget.conversation.multiHost
                  ? '这个对话可以操作全部主机，用哪台由它自己选。'
                  : '这个对话只管一台主机，记忆也单独存在这台机器名下。',
              style: const TextStyle(fontSize: 12.5, height: 1.6, color: C.grey),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AgentSession? session = _session;
    return Column(
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: const BoxDecoration(
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
          ),
          child: Row(
            children: <Widget>[
              IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back, size: 19, color: C.ink),
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      widget.conversation.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    Text(widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: C.monoSmall),
                  ],
                ),
              ),
              Text('${session?.loop.step ?? 0}/${session?.loop.maxSteps ?? 0}',
                  style: C.monoSmall),
              const SizedBox(width: 10),
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
                const SizedBox(width: 30),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _thread(),
            ),
          ),
        ),
        if (_pending != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ApprovalCard(
              request: _pending!,
              onDecide: _decide,
              onAllowKind: _allowKind,
              onAllowAll: _allowAll,
              kindLabel: _kind,
            ),
          ),
        if (_attachNames.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (int i = 0; i < _attachNames.length; i += 1)
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                    decoration: BoxDecoration(
                      color: C.blueSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(_attachNames[i],
                            style: C.monoSmall.copyWith(color: C.blue, fontSize: 10.5)),
                        GestureDetector(
                          onTap: () => setState(() {
                            _attachNames.removeAt(i);
                            if (i < _images.length) _images.removeAt(i);
                          }),
                          child: const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(Icons.close, size: 13, color: C.blue),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
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
              children: <Widget>[
                GestureDetector(
                  onTap: _running ? null : _pickFiles,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(Icons.add_circle_outline, size: 20, color: C.grey),
                  ),
                ),
                const SizedBox(width: 7),
                const Text('❯', style: TextStyle(fontSize: 14, color: C.blue)),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_running && session != null,
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(hintText: '接着说，或者让它停'),
                  ),
                ),
                GestureDetector(
                  onTap: (_running || session == null) ? null : _send,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: (_running || session == null) ? C.rule2 : C.blue,
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
