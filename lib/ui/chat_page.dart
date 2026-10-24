import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/conversation.dart';
import '../core/docx.dart';
import '../core/models.dart';
import '../data/hub.dart';
import '../services.dart';
import '../tools/ask_tool.dart';
import 'components.dart';
import 'md_text.dart';
import 'theme.dart';

/// 解过的照片放在这里，重画一帧不用再把 base64 拆一次。
final Map<String, Uint8List> _photoCache = <String, Uint8List>{};

/// 从 `data:image/…;base64,…` 里取出字节。没带前缀或解不开就给 null。
Uint8List? photoBytes(String url) {
  final Uint8List? hit = _photoCache[url];
  if (hit != null) return hit;
  final int comma = url.indexOf(',');
  if (comma < 0 || !url.startsWith('data:')) return null;
  try {
    final Uint8List bytes = base64Decode(url.substring(comma + 1));
    if (_photoCache.length > 24) _photoCache.clear();
    _photoCache[url] = bytes;
    return bytes;
  } catch (_) {
    return null;
  }
}

/// One conversation. Its transcript lives on disk, so leaving and coming back
/// keeps everything.
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.services,
    required this.hub,
    required this.conversation,
    required this.subtitle,
    required this.onBack,
  });

  final AppServices services;
  final SessionHub hub;
  final Conversation conversation;
  final String subtitle;
  final VoidCallback onBack;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  LiveSession? _live;

  /// 读者翻上去了：右下角给一个回到底部的按钮。
  bool _atBottom = true;

  /// 刚进来时先跳到最新那条，不用等人先往下翻。
  bool _opened = false;
  Timer? _openJump;
  final List<String> _images = <String>[];
  final List<String> _attachNames = <String>[];

  /// 和 `_attachNames` 一一对应：图片那一格是 data URL，文本文件那一格是空串。
  final List<String> _attachPhotos = <String>[];

  List<LlmMessage> get _messages => widget.conversation.messages;

  /// 这一轮是不是在跑，看托管处，不看页面自己。
  bool get _running => _live?.running ?? false;

  AgentLoop? get _loop => _live?.loop;

  ApprovalRequest? get _pending => _live?.pending;

  String get _kind => _live?.pendingKind ?? '';

  @override
  void initState() {
    super.initState();
    widget.hub.addListener(_refresh);
    _scroll.addListener(_onScroll);
    _attach();
  }

  /// 拿到这个对话的活会话。已经有一个在跑就用那一个，不另起一份。
  Future<void> _attach() async {
    final LiveSession live = await widget.hub.open(widget.conversation);
    if (!mounted) return;
    setState(() => _live = live);
    _followTail();
    _jumpOnOpen();
  }

  /// 进对话先落在最底下那一条。图片解码后高度会变，所以补跳两次。
  void _jumpOnOpen() {
    _openJump?.cancel();
    _toEnd();
    _openJump = Timer(const Duration(milliseconds: 90), _toEnd);
    Timer(const Duration(milliseconds: 260), () {
      _toEnd();
      _opened = true;
    });
  }

  void _toEnd() {
    if (!mounted || !_scroll.hasClients) return;
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
    if (!_atBottom) setState(() => _atBottom = true);
  }

  @override
  void dispose() {
    _openJump?.cancel();
    widget.hub.removeListener(_refresh);
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final bool atBottom = _scroll.position.maxScrollExtent - _scroll.position.pixels < 200;
    if (atBottom == _atBottom) return;
    setState(() => _atBottom = atBottom);
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _followTail();
  }

  /// 跟着尾巴走，但读者往上翻看旧内容时不要把他拽回来。
  void _followTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final ScrollPosition p = _scroll.position;
      // 刚打开的那几帧不看他翻到哪儿了，直接落到最新一条。
      if (_opened && p.maxScrollExtent - p.pixels > 180) return;
      _scroll.jumpTo(p.maxScrollExtent);
    });
  }

  Future<void> _allowKind() async {
    final LiveSession? live = _live;
    if (live == null) return;
    final String kind = live.pendingKind;
    if (kind.isNotEmpty && !widget.conversation.kindApprovals.contains(kind)) {
      widget.conversation.kindApprovals.add(kind);
      await widget.services.persist(widget.conversation);
    }
    live.decide(true);
  }

  Future<void> _allowAll() async {
    widget.conversation.autoApproveAll = true;
    await widget.services.persist(widget.conversation);
    _live?.decide(true);
  }

  void _decide(bool allowed) => _live?.decide(allowed);

  Future<void> _send() async {
    final LiveSession? live = _live;
    final String text = _input.text.trim();
    if (live == null || live.running) return;
    if (text.isEmpty && _images.isEmpty) return;
    _input.clear();
    final List<String> images = List<String>.of(_images);
    _images.clear();
    _attachNames.clear();
    _attachPhotos.clear();
    setState(() {});
    // 交给托管处跑：切到别的对话、回到列表，这一轮都还在。
    await widget.hub.send(live, text, images: images);
    if (!mounted) return;
    setState(() {});
  }

  void _stop() {
    final LiveSession? live = _live;
    if (live != null) widget.hub.stop(live);
  }

  /// 只换这个对话的提示词：写了就自己用一份，留空就回到设置里那份。
  Future<void> _editPrompt() async {
    final Conversation c = widget.conversation;
    final TextEditingController ctrl = TextEditingController(text: c.systemPrompt);
    final bool follows = c.systemPrompt.trim().isEmpty;
    final String? saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0x00000000),
      builder: (BuildContext ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: C.paper,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Text('这个对话的提示词',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: C.grey,
                      minimumSize: const Size(0, 34),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('取消'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                follows ? '现在跟设置里的那份走。在这里写就是只换这个对话。' : '这个对话用自己的一份，不跟设置走。',
                style: const TextStyle(fontSize: 11.5, color: C.grey, height: 1.6),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: C.card,
                  borderRadius: BorderRadius.circular(C.radiusSmall),
                  border: Border.all(color: C.rule),
                ),
                child: TextField(
                  controller: ctrl,
                  minLines: 6,
                  maxLines: 14,
                  style: C.mono.copyWith(fontSize: 12.5),
                  decoration: const InputDecoration(hintText: '留空就是用设置里那份'),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: SquareButton(
                      label: '跟设置走',
                      tone: 'ink',
                      onPressed: () => Navigator.of(ctx).pop(''),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SquareButton(
                      label: '存到这个对话',
                      filled: true,
                      onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    ctrl.dispose();
    if (saved == null || !mounted) return;
    c.systemPrompt = saved.trim();
    await widget.services.persist(c);
    final LiveSession? live = _live;
    if (live != null) {
      live.loop.systemPrompt = promptFor(widget.services.settings, c);
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(saved.trim().isEmpty ? '这个对话改回跟设置走。' : '这个对话换成了自己的一份。')),
    );
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
        final String url = 'data:$mime;base64,${base64Encode(bytes)}';
        _images.add(url);
        _attachNames.add(f.name);
        _attachPhotos.add(url);
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
    _attachPhotos.add('');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
        out.add(_userTurn(m));
      } else if (m.role == LlmRole.assistant) {
        if (m.text.trim().isNotEmpty) out.add(_answer(m.text));
        if (m.calls.isNotEmpty) out.add(_toolTurn(m.calls, outputs, runningId));
      }
    }
    final String partial = _loop?.partial ?? '';
    if (partial.isNotEmpty) out.add(_answer(partial, streaming: true));
    if (_running && partial.isEmpty) {
      out.add(_ThinkingRow(phase: _loop?.phase ?? AgentPhase.thinking));
    }
    if (out.isEmpty) out.add(_empty());
    return out;
  }

  Widget _userTurn(LlmMessage message) {
    final String text = message.text;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (text.trim().isNotEmpty) Text(text, style: C.ask),
                if (message.images.isNotEmpty) ...<Widget>[
                  if (text.trim().isNotEmpty) const SizedBox(height: 9),
                  _photoStrip(message.images),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 一轮里带的照片：小图排一行，点开看大图。
  Widget _photoStrip(List<String> photos) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (int i = 0; i < photos.length; i += 1)
          GestureDetector(
            onTap: () => _openPhoto(photos, i),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(C.radiusSmall),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: C.paper2,
                  border: Border.all(color: C.rule2),
                  borderRadius: BorderRadius.circular(C.radiusSmall),
                ),
                child: _photoImage(photos[i], fit: BoxFit.cover),
              ),
            ),
          ),
      ],
    );
  }

  Widget _photoImage(String url, {required BoxFit fit}) {
    final Uint8List? bytes = photoBytes(url);
    if (bytes == null) {
      return const Center(
        child: Text('读不出这张图',
            style: TextStyle(fontSize: 11, color: C.grey2)),
      );
    }
    return Image.memory(
      bytes,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (BuildContext ctx, Object error, StackTrace? stack) =>
          const Center(
        child: Text('读不出这张图',
            style: TextStyle(fontSize: 11, color: C.grey2)),
      ),
    );
  }

  /// 点开一张：全屏、可拖动放大，点一下退出。
  void _openPhoto(List<String> photos, int start) {
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: const Color(0xF2181C23),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b) =>
          _PhotoViewer(photos: photos, start: start),
      transitionsBuilder:
          (BuildContext ctx, Animation<double> a, Animation<double> b, Widget child) =>
              FadeTransition(opacity: a, child: child),
    ));
  }

  Widget _answer(String text, {bool streaming = false}) {
    return Padding(
      padding: EdgeInsets.only(left: 34, bottom: streaming ? 6 : 18),
      child: MdText(
        text: text,
        streaming: streaming,
        base: C.answer.copyWith(fontSize: widget.services.settings.value.answerFont),
      ),
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
  Widget _usage(AgentLoop? loop) {
    if (loop == null) return const SizedBox.shrink();
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
          Text('第 ${loop.step}/${loop.maxSteps} 步',
              style: C.monoSmall.copyWith(color: C.blue)),
        ],
      );
    }
    final double hit = loop.cacheHitRate;
    return Text(
      '${_fmtTokens(loop.tokens)} tok${hit > 0 ? ' · 命中 ${(hit * 100).round()}%' : ''}',
      style: C.monoSmall.copyWith(color: hit > 0 ? C.blue : C.grey2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AgentLoop? loop = _loop;
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
              const SizedBox(width: 6),
              GestureDetector(
                onTap: _editPrompt,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox(
                  width: 30,
                  height: 30,
                  child: Icon(Icons.tune, size: 17, color: C.grey),
                ),
              ),
              const SizedBox(width: 4),
              Flexible(child: _usage(loop)),
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
          child: Stack(
            children: <Widget>[
              // 对话里的字都能选中，长按就能复制。
              Positioned.fill(
                child: SelectionArea(
                  child: SingleChildScrollView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _thread(),
                    ),
                  ),
                ),
              ),
              if (!_atBottom)
                Positioned(
                  right: 16,
                  bottom: 12,
                  child: GestureDetector(
                    onTap: _jumpToBottom,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.card,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: C.rule2),
                        boxShadow: C.softShadow,
                      ),
                      child: const Icon(Icons.arrow_downward, size: 17, color: C.blue),
                    ),
                  ),
                ),
            ],
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
        if (_live?.pendingAsk != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: _AskCard(
              request: _live!.pendingAsk!,
              onAnswer: (String text) => _live?.answerAsk(text),
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
                    padding: EdgeInsets.fromLTRB(
                        i < _attachPhotos.length && _attachPhotos[i].isNotEmpty ? 4 : 10,
                        4,
                        6,
                        4),
                    decoration: BoxDecoration(
                      color: C.blueSoft,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (i < _attachPhotos.length && _attachPhotos[i].isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(
                                width: 26,
                                height: 26,
                                child: _photoImage(_attachPhotos[i], fit: BoxFit.cover),
                              ),
                            ),
                          ),
                        Text(_attachNames[i],
                            style: C.monoSmall.copyWith(color: C.blue, fontSize: 10.5)),
                        GestureDetector(
                          onTap: () => setState(() {
                            _attachNames.removeAt(i);
                            if (i < _images.length) _images.removeAt(i);
                            if (i < _attachPhotos.length) _attachPhotos.removeAt(i);
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
                    enabled: !_running && loop != null,
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
                  onTap: (_running || loop == null) ? null : _send,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: (_running || loop == null) ? C.rule2 : C.blue,
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

/// 模型问人的那张卡。有选项就点，没有就自己写，答完它接着干。
class _AskCard extends StatefulWidget {
  const _AskCard({required this.request, required this.onAnswer});

  final AskRequest request;
  final void Function(String text) onAnswer;

  @override
  State<_AskCard> createState() => _AskCardState();
}

class _AskCardState extends State<_AskCard> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _send() {
    final String text = _text.text.trim();
    if (text.isEmpty) return;
    _text.clear();
    widget.onAnswer(text);
  }

  @override
  Widget build(BuildContext context) {
    return CardBox(
      border: const Color(0xFFD9DEF7),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: C.blueSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('在问你',
                    style: C.label.copyWith(color: C.blue, fontSize: 9.5, letterSpacing: 1)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(widget.request.question, style: C.answer),
          if (widget.request.options.isNotEmpty) ...<Widget>[
            const SizedBox(height: 11),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String option in widget.request.options)
                  GestureDetector(
                    onTap: () => widget.onAnswer(option),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: C.card,
                        borderRadius: BorderRadius.circular(C.radiusSmall),
                        border: Border.all(color: C.blue),
                      ),
                      child: Text(option,
                          style: const TextStyle(fontSize: 12, color: C.blue)),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 11),
          Row(
            children: <Widget>[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: C.card,
                    borderRadius: BorderRadius.circular(C.radiusSmall),
                    border: Border.all(color: C.rule),
                  ),
                  child: TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(fontSize: 13.5, height: 1.5),
                    decoration: const InputDecoration(hintText: '也可以自己写一句'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SquareButton(label: '回答', filled: true, onPressed: _send),
            ],
          ),
        ],
      ),
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

/// 全屏看一张照片：左右翻、双指放大，点一下退出。
class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.photos, required this.start});

  final List<String> photos;
  final int start;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _page =
      PageController(initialPage: widget.start.clamp(0, widget.photos.length - 1));
  late int _index = widget.start;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Scaffold(
        backgroundColor: const Color(0x00000000),
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              PageView.builder(
                controller: _page,
                itemCount: widget.photos.length,
                onPageChanged: (int i) => setState(() => _index = i),
                itemBuilder: (BuildContext ctx, int i) => InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: Center(
                    child: photoBytes(widget.photos[i]) == null
                        ? const Text('读不出这张图',
                            style: TextStyle(color: C.onInk, fontSize: 13))
                        : Image.memory(
                            photoBytes(widget.photos[i])!,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                child: Center(
                  child: Text(
                    widget.photos.length > 1
                        ? '${_index + 1} / ${widget.photos.length}'
                        : '',
                    style: const TextStyle(
                        fontSize: 12, color: C.onInk, letterSpacing: 0.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
