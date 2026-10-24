import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/conversation.dart';
import '../core/docx.dart';
import '../core/llm_base.dart';
import '../core/models.dart';
import '../data/foreground.dart';
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
  DateTime _lastNote = DateTime.fromMillisecondsSinceEpoch(0);
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
    session.loop.tokens = widget.conversation.tokensUsed;
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

  /// Follow the tail while it grows, but leave the view alone once the reader
  /// has scrolled up to re-read something.
  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _noteProgress();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final ScrollPosition p = _scroll.position;
      if (p.maxScrollExtent - p.pixels > 180) return;
      _scroll.jumpTo(p.maxScrollExtent);
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
    _lastNote = DateTime.fromMillisecondsSinceEpoch(0);
    final CancelToken token = CancelToken();
    _cancel = token;
    // 手机上挂一条前台通知：切出去看别的、锁屏，这一轮也不会被系统掐掉。
    unawaited(ForegroundTask.begin('第 1 步'));
    try {
      session.loop.maxSteps = widget.services.settings.value.maxSteps;
      final List<String> images = List<String>.of(_images);
      _images.clear();
      _attachNames.clear();
      await session.loop.send(text, cancel: token, images: images);
      widget.conversation.tokensUsed = session.loop.tokens;
      await widget.services.persist(widget.conversation);
    } finally {
      unawaited(ForegroundTask.end());
      if (mounted) setState(() => _running = false);
    }
  }

  /// 通知上那句进度：走到第几步、在等什么。不用每 60 毫秒改一次。
  void _noteProgress() {
    if (!_running) return;
    final AgentLoop? loop = _session?.loop;
    if (loop == null) return;
    final DateTime now = DateTime.now();
    if (now.difference(_lastNote).inMilliseconds < 1200) return;
    _lastNote = now;
    final String where = switch (loop.phase) {
      AgentPhase.thinking => '等模型回话',
      AgentPhase.acting => '执行命令',
      AgentPhase.waiting => '等你确认',
      AgentPhase.idle => '收尾',
    };
    unawaited(ForegroundTask.update('第 ${loop.step}/${loop.maxSteps} 步 · $where'));
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
        _addText(f.name, utf8.decode(bytes, allowMalformed: true));
        continue;
      }
      if (name.endsWith('.docx')) {
        final String? body = docxText(bytes);
        if (body == null) {
          _toast('${f.name} 里没读出文字，另存一份 .docx 再试。');
          continue;
        }
        _addText(f.name, body);
        continue;
      }
      _toast('${f.name} 的类型还读不了，现在支持图片、纯文本和 Word（.docx）。');
    }
    if (mounted) setState(() {});
  }

  /// 把一个文本文件拼进输入框：太长就截，提示一句。
  void _addText(String name, String body) {
    if (body.length > 60000) {
      _toast('$name 太长了，先截前 60000 字。');
    }
    final String clipped = body.length > 60000 ? body.substring(0, 60000) : body;
    _input.text = '${_input.text}${_input.text.isEmpty ? '' : '\n\n'}'
        '文件 $name：\n\n```\n$clipped\n```';
    _attachNames.add(name);
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
        out.add(_userTurn(m.text));
      } else if (m.role == LlmRole.assistant) {
        if (m.text.trim().isNotEmpty) out.add(_answer(m.text));
        if (m.calls.isNotEmpty) out.add(_toolTurn(m.calls, outputs, runningId));
      }
    }
    final String partial = _session?.loop.partial ?? '';
    if (partial.isNotEmpty) out.add(_answer(partial, streaming: true));
    if (_running && partial.isEmpty) {
      out.add(_ThinkingRow(phase: _session?.loop.phase ?? AgentPhase.thinking));
    }
    if (out.isEmpty) out.add(_empty());
    return out;
  }

  Widget _userTurn(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: C.blueSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('❯',
                style: TextStyle(fontSize: 12, color: C.blue, height: 1.1)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: C.ask)),
        ],
      ),
    );
  }

  Widget _answer(String text, {bool streaming = false}) {
    final TextStyle style = C.answer;
    return Padding(
      padding: EdgeInsets.only(left: 34, bottom: streaming ? 6 : 18),
      child: streaming
          ? Text.rich(
              TextSpan(
                children: <TextSpan>[
                  TextSpan(text: text),
                  const TextSpan(text: ' ▍', style: TextStyle(color: C.blue)),
                ],
              ),
              style: style,
            )
          : Text(text, style: style),
    );
  }

  Widget _toolTurn(List<LlmToolCall> calls, Map<String, String> outputs, String runningId) {
    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: 18),
      child: ToolRunGroup(calls: calls, outputs: outputs, runningId: runningId),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('说说要做什么',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 10),
          const Text('比如：看看磁盘，把 nginx 的老日志清一下。', style: C.answer),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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

  static String _fmtTokens(int n) {
    if (n < 1000) return '$n';
    final double k = n / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0)}k';
  }

  /// While a turn is running the header answers 「它还在跑吗」; when idle it
  /// shows what the conversation has spent.
  Widget _usage(AgentSession? session) {
    if (session == null) return const SizedBox.shrink();
    if (_running) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 11,
            height: 11,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: C.blue),
          ),
          const SizedBox(width: 7),
          Text('第 ${session.loop.step}/${session.loop.maxSteps} 步',
              style: C.monoSmall.copyWith(color: C.blue)),
        ],
      );
    }
    final double hit = session.loop.cacheHitRate;
    return Text(
      '${_fmtTokens(session.loop.tokens)} tok${hit > 0 ? ' · 命中 ${(hit * 100).round()}%' : ''}',
      style: C.monoSmall.copyWith(color: hit > 0 ? C.blue : C.grey2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AgentSession? session = _session;
    return Column(
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
          ),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: widget.onBack,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(Icons.arrow_back, size: 19, color: C.ink),
                ),
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
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: C.monoSmall),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(child: _usage(session)),
              const SizedBox(width: 10),
              if (_running)
                GestureDetector(
                  onTap: _stop,
                  child: Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: C.card,
                      borderRadius: BorderRadius.circular(C.radiusSmall),
                      border: Border.all(color: C.rule2),
                    ),
                    child: Container(width: 9, height: 9, color: C.body),
                  ),
                )
              else
                const SizedBox(width: 32),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _thread(),
            ),
          ),
        ),
        if (_pending != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
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
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
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
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            decoration: BoxDecoration(
              color: C.card,
              borderRadius: BorderRadius.circular(C.radius),
              border: Border.all(color: C.rule),
              boxShadow: C.softShadow,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                GestureDetector(
                  onTap: _running ? null : _pickFiles,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8, right: 6, left: 2),
                    child: Icon(Icons.add_circle_outline,
                        size: 21, color: _running ? C.rule2 : C.grey),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 9),
                  child: Text('❯', style: TextStyle(fontSize: 14, color: C.blue)),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_running && session != null,
                    style: const TextStyle(fontSize: 14.5, height: 1.5),
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: '交给它一件事',
                      contentPadding: EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: (_running || session == null) ? null : _send,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (_running || session == null) ? C.rule2 : C.blue,
                      borderRadius: BorderRadius.circular(C.radiusSmall),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.arrow_upward, size: 19, color: Colors.white),
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

/// The live line at the tail of the transcript: three breathing dots, what the
/// loop is doing, and how long it has been doing it.
class _ThinkingRow extends StatefulWidget {
  const _ThinkingRow({required this.phase});

  final AgentPhase phase;

  @override
  State<_ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<_ThinkingRow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();
  Timer? _tick;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds += 1);
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    _tick?.cancel();
    super.dispose();
  }

  String get _label {
    switch (widget.phase) {
      case AgentPhase.thinking:
        return '正在想';
      case AgentPhase.acting:
        return '正在执行';
      case AgentPhase.waiting:
        return '等你批准';
      case AgentPhase.idle:
        return '正在收尾';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: 14),
      child: Row(
        children: <Widget>[
          AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? child) {
              return Row(
                children: <Widget>[
                  for (int i = 0; i < 3; i += 1)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Opacity(
                        opacity: _fade(i),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: const BoxDecoration(color: C.blue, shape: BoxShape.circle),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(width: 6),
          Text('$_label · $_seconds 秒',
              style: C.monoSmall.copyWith(color: C.grey, fontSize: 11)),
        ],
      ),
    );
  }

  double _fade(int i) {
    final double p = (_pulse.value + i / 3) % 1;
    final double wave = p < 0.5 ? p * 2 : (1 - p) * 2;
    return 0.25 + 0.75 * wave;
  }
}
