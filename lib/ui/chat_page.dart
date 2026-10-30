import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/balance.dart';
import '../core/compact.dart';
import '../core/conversation.dart';
import '../core/deepseek.dart';
import '../core/docx.dart';
import '../core/greeting.dart';
import '../core/models.dart';
import '../core/plan.dart';
import '../core/poems.dart';
import '../core/pricing.dart';
import '../data/balance.dart';
import '../data/hub.dart';
import '../data/llm_settings.dart';
import '../data/settings.dart';
import '../services.dart';
import '../tools/ask_tool.dart';
import 'components.dart';
import 'md_text.dart';
import 'motion.dart';
import 'output_preview.dart';
import 'pet.dart';
import 'plan_bar.dart';
import 'temp_files_page.dart';
import 'theme.dart';
import 'trace_page.dart';

/// 解过的照片放在这里，重画一帧不用再把 base64 拆一次。留八张就够屏幕上那几行看，
/// 每张解出来是几兆，留多了长对话里的内存全压在照片上。
final Map<String, Uint8List> _photoCache = <String, Uint8List>{};

/// 从 `data:image/…;base64,…` 里取出字节。没带前缀或解不开就给 null。
Uint8List? photoBytes(String url) {
  final Uint8List? hit = _photoCache[url];
  if (hit != null) return hit;
  final int comma = url.indexOf(',');
  if (comma < 0 || !url.startsWith('data:')) return null;
  try {
    final Uint8List bytes = base64Decode(url.substring(comma + 1));
    if (_photoCache.length > 8) _photoCache.clear();
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
    this.onOpenSidebar,
  });

  final AppServices services;
  final SessionHub hub;
  final Conversation conversation;
  final String subtitle;
  final VoidCallback onBack;

  /// 窄屏时顶上那颗换成菜单，点开是会话侧边栏；宽屏是 null，用返回箭头。
  final VoidCallback? onOpenSidebar;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 输入框拿到焦点时边框亮一下，人就知道字往哪儿落。
  final FocusNode _focus = FocusNode();
  bool _typing = false;
  LiveSession? _live;

  /// 读者翻上去了：右下角给一个回到底部的按钮。
  bool _atBottom = true;

  /// 正在往底跳：这几帧里滚动位置一直在变，别把它当成读者往上翻。
  bool _settling = false;

  /// 正在追尾巴：同一条尾巴不叠两次动画。
  bool _chasing = false;
  Timer? _openJump;
  final List<String> _images = <String>[];
  final List<String> _attachNames = <String>[];

  /// 和 `_attachNames` 一一对应：图片那一格是 data URL，文本文件那一格是空串。
  final List<String> _attachPhotos = <String>[];

  List<LlmMessage> get _messages => widget.conversation.messages;

  /// 账上还剩多少：问得到的服务才显示，点一下那个数字重问一次。
  late final BalanceStore _balance =
      BalanceStore(widget.services.settings, widget.services.secrets);

  /// 这一轮是不是在跑，看托管处，不看页面自己。
  bool get _running => _live?.running ?? false;

  /// 记录里还有没有能退回去的那一句。
  bool get _canRollback =>
      !_running && _messages.any((LlmMessage m) => m.role == LlmRole.user);

  AgentLoop? get _loop => _live?.loop;

  /// 贴在输入框上面那两张卡（待批准 / 在问你）最高多少：按看得见的高度算，
  /// 扣掉键盘。内容一长卡片自己滚，按钮不跟着跑。
  double get _pinnedMax {
    final MediaQueryData mq = MediaQuery.of(context);
    final double visible = mq.size.height - mq.viewInsets.bottom - mq.padding.top;
    final double h = visible * 0.46;
    return h < 200 ? 200 : h;
  }

  ApprovalRequest? get _pending => _live?.pending;

  String get _kind => _live?.pendingKind ?? '';

  @override
  void initState() {
    super.initState();
    widget.hub.addListener(_refresh);
    _balance.addListener(_onBalance);
    // 第一帧之后再问：建这个页面的当口同步 setState 会撞上「during build」。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_balance.refresh(_profile));
    });
    _scroll.addListener(_onScroll);
    _focus.addListener(_onFocus);
    _attach();
  }

  void _onBalance() {
    if (mounted) setState(() {});
  }

  void _onFocus() {
    if (_focus.hasFocus == _typing) return;
    setState(() => _typing = _focus.hasFocus);
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
    Timer(const Duration(milliseconds: 260), _toEnd);
  }

  void _toEnd() {
    if (!mounted || !_scroll.hasClients) return;
    _settle(0);
  }

  /// 懒表只知道已经排过的行有多高，末尾那段是先估出来的：跳一次到不了底，
  /// 就等这一帧排完再跳。跳到底之前不去动「翻上去了」那个按钮。
  void _settle(int round) {
    if (!mounted || !_scroll.hasClients) return;
    _settling = true;
    final ScrollPosition p = _scroll.position;
    if (p.maxScrollExtent > p.pixels) p.jumpTo(p.maxScrollExtent);
    if (round >= 40) {
      _settling = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        _settling = false;
        return;
      }
      final ScrollPosition q = _scroll.position;
      if (q.maxScrollExtent - q.pixels <= 1) {
        _settling = false;
        if (!_atBottom) setState(() => _atBottom = true);
        return;
      }
      _settle(round + 1);
    });
  }

  @override
  void dispose() {
    _openJump?.cancel();
    widget.hub.removeListener(_refresh);
    _balance.removeListener(_onBalance);
    _balance.dispose();
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 离底多少像素以内还算「在底部」。只差几十像素不该停止跟随。
  static const double _tailSlack = 56;

  bool get _nearTail {
    if (!_scroll.hasClients) return true;
    final ScrollPosition p = _scroll.position;
    return p.maxScrollExtent - p.pixels <= _tailSlack;
  }

  void _onScroll() {
    if (_settling || !_scroll.hasClients) return;
    final bool atBottom = _nearTail;
    if (atBottom == _atBottom) return;
    setState(() => _atBottom = atBottom);
  }

  /// 点右下角那颗：一段一段追下去，直到真的落底。
  ///
  /// 行是边滚边建的，末尾高度先是估的，一次动画到不了底，所以要接着追。
  Future<void> _jumpToBottom() async {
    if (!_scroll.hasClients) return;
    if (!_atBottom) setState(() => _atBottom = true);
    _settling = true;
    for (int i = 0; i < 30; i += 1) {
      if (!mounted || !_scroll.hasClients) break;
      final ScrollPosition p = _scroll.position;
      final double gap = p.maxScrollExtent - p.pixels;
      if (gap <= 1) break;
      await _scroll.animateTo(
        p.maxScrollExtent,
        duration: Duration(milliseconds: gap > 900 ? 260 : 170),
        curve: Curves.easeOutCubic,
      );
      await WidgetsBinding.instance.endOfFrame;
    }
    _settling = false;
    if (mounted) setState(() => _atBottom = true);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {});
    _followTail();
  }

  /// 跟着尾巴走，但读者往上翻看旧内容时不要把他拽回来。
  void _followTail() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _chase());
  }

  /// 平滑追一次尾巴。字还在往外冒的时候每几十毫秒追一下，看上去才是跟着走。
  Future<void> _chase() async {
    if (!mounted || !_scroll.hasClients || !_atBottom || _chasing || _settling) return;
    _chasing = true;
    try {
      for (int i = 0; i < 8; i += 1) {
        if (!mounted || !_scroll.hasClients || !_atBottom) break;
        final ScrollPosition p = _scroll.position;
        final double gap = p.maxScrollExtent - p.pixels;
        if (gap <= 1) break;
        await _scroll.animateTo(
          p.maxScrollExtent,
          duration: Duration(milliseconds: gap > 400 ? 200 : 110),
          curve: Curves.easeOut,
        );
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      _chasing = false;
    }
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
    // 刚花过钱，余额顺手再问一句（十二秒内只问一次）。
    unawaited(_balance.refresh(_profile));
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
          decoration: BoxDecoration(
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
                follows ? '现在跟这套配置的提示词走（没配就是设置里那份）。在这里写就是只换这个对话。' : '这个对话用自己的一份，不跟设置走。',
                style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6),
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

  /// 顶栏那三颗里的第一颗：这个对话自己的事，提示词和压缩。
  /// 退一步：把最后那句提问和它后面的一起删掉，那句话放回输入框。
  ///
  /// 跑不动的、模型拒了的那一轮用得上：退回去改两个字再发，
  /// 不用重开一场对话，也不用看着一段报错留在记录里。
  Future<bool> _rollback() async {
    if (_running) {
      _toast('这一轮还在跑，先停下再退。');
      return false;
    }
    final List<LlmMessage> msgs = _messages;
    int at = -1;
    for (int i = msgs.length - 1; i >= 0; i -= 1) {
      if (msgs[i].role == LlmRole.user) {
        at = i;
        break;
      }
    }
    if (at < 0) {
      _toast('这场对话里还没有可退的那一句。');
      return false;
    }
    final String text = msgs[at].text;
    msgs.removeRange(at, msgs.length);
    _live?.loop.onHistoryChanged();
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    await widget.services.persist(widget.conversation);
    if (!mounted) return true;
    setState(() {});
    _focus.requestFocus();
    return true;
  }

  Future<void> _moreSheet() async {
    final int cut = compactCut(_messages);
    final String? pick = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => SheetCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('这场对话',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.ink)),
            const SizedBox(height: 3),
            Text('压缩只动更早的那些，后面几条原样留着。', style: C.monoSmall),
            const SizedBox(height: 14),
            _sheetRow(
              Icons.tune,
              '这场对话的提示词',
              widget.conversation.systemPrompt.trim().isEmpty ? '现在跟设置走' : '用自己的一份',
              true,
              () => Navigator.of(ctx).pop('prompt'),
            ),
            const SizedBox(height: 8),
            _sheetRow(
              Icons.undo_rounded,
              '回退一步',
              _canRollback ? '删掉最后那句提问和它后面的，放回输入框' : '没有可退的那一句',
              _canRollback,
              () => Navigator.of(ctx).pop('rollback'),
            ),
            const SizedBox(height: 8),
            _sheetRow(
              Icons.compress,
              '压缩对话',
              cut <= 0
                  ? '前面对话还短，不用压'
                  : (_running ? '这一轮还在跑，跑完再压' : '把前面 $cut 条收成一段摘要'),
              cut > 0 && !_running,
              () => Navigator.of(ctx).pop('compact'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (!mounted || pick == null) return;
    if (pick == 'prompt') {
      await _editPrompt();
      return;
    }
    if (pick == 'rollback') {
      await _rollback();
      return;
    }
    await _compact();
  }

  /// 把更早的那一段交给模型收成一段摘要：原文从记录里删掉，留下的那一段代替它。
  Future<void> _compact() async {
    final LiveSession? live = _live;
    if (live == null) return;
    if (_running) {
      _toast('这一轮还在跑，跑完再压。');
      return;
    }
    final int cut = compactCut(_messages);
    if (cut <= 0) {
      _toast('这场对话还短，不用压缩。');
      return;
    }
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('压缩这场对话？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('前面的 $cut 条会收成一段摘要，原文不再留在记录里。后面几条不动。',
            style: const TextStyle(fontSize: 13, height: 1.6)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('再想想', style: TextStyle(fontSize: 13, color: C.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('压缩', style: TextStyle(fontSize: 13, color: C.blue)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final String note = await widget.hub.compact(live);
    if (!mounted) return;
    setState(() {});
    _toast(note.isEmpty ? '没压成，模型没回话。' : '前面 $cut 条收成一段摘要了。');
  }

  Widget _summaryCard(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: _SummaryCard(text: text),
    );
  }

  /// 加号先问一句：这一条消息带文件，还是去临时文件区。
  Future<void> _attachSheet() async {
    final bool running = _running;
    final String? pick = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => SheetCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('给它带东西',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.ink)),
            const SizedBox(height: 3),
            Text(running ? '这一轮还在跑，跑完再进文件。' : '文件跟着下一条消息一起发出去。',
                style: C.monoSmall),
            const SizedBox(height: 14),
            _sheetRow(
              Icons.attach_file,
              '进对话',
              '图片、纯文本、Word',
              !running,
              () => Navigator.of(ctx).pop('pick'),
            ),
            const SizedBox(height: 8),
            _sheetRow(
              Icons.folder_open_outlined,
              '临时文件区',
              '模型写的文件在这里，能传到主机',
              true,
              () => Navigator.of(ctx).pop('temp'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (!mounted || pick == null) return;
    if (pick == 'pick') {
      await _pickFiles();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TempFilesPage(
          files: widget.services.files,
          hosts: widget.services.hosts,
          pool: widget.services.pool,
        ),
      ),
    );
  }

  Widget _sheetRow(
    IconData icon,
    String title,
    String note,
    bool enabled,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
        decoration: BoxDecoration(
          color: C.paper2,
          borderRadius: BorderRadius.circular(C.radiusSmall),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: enabled ? C.ink : C.rule2),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title,
                      style: TextStyle(fontSize: 13, color: enabled ? C.ink : C.grey2)),
                  const SizedBox(height: 2),
                  Text(note, style: C.monoSmall),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: C.grey2),
          ],
        ),
      ),
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

  String _runningId(Map<String, String> outputs) {
    if (!_running) return '';
    for (final LlmMessage m in _messages) {
      if (m.role != LlmRole.assistant) continue;
      for (final LlmToolCall c in m.calls) {
        if (!outputs.containsKey(c.id)) return c.id;
      }
    }
    return '';
  }

  /// 这一屏有哪几行。只算行，不拆字也不排版：几万字的记录按需才画。
  List<_Row> _rows() {
    final List<_Row> rows = <_Row>[];
    final int dropped = widget.conversation.dropped;
    if (dropped > 0) {
      rows.add(_Row(_RowKind.trim, text: '更早的 $dropped 条已收起'));
    }
    final WorkPlan? plan = widget.conversation.plan;
    final bool planDone = plan != null && plan.finished;
    final int anchor = widget.conversation.planAnchor;
    for (int i = 0; i < _messages.length; i += 1) {
      final LlmMessage m = _messages[i];
      // 做完的计划不再钉在顶上，而是留在当时那一段对话的末尾。
      if (planDone && i == anchor) {
        rows.add(const _Row(_RowKind.plan));
      }
      if (m.role == LlmRole.user) {
        rows.add(_Row(_RowKind.user, message: m));
      } else if (m.role == LlmRole.assistant) {
        if (m.text.startsWith(kCompactMark)) {
          rows.add(_Row(_RowKind.summary, message: m));
          continue;
        }
        if (m.text.trim().isNotEmpty) {
          rows.add(_Row(_RowKind.answer, message: m, text: m.text));
        }
        if (m.calls.isNotEmpty) rows.add(_Row(_RowKind.tool, message: m));
      }
    }
    // 计划是在最后一条之后做完的：它排在那一段的末尾。
    if (planDone && anchor >= _messages.length) {
      rows.add(const _Row(_RowKind.plan));
    }
    // 没活干的时候，记录最后面躺一只睡着的。
    if (!_running && rows.isNotEmpty && rows.last.kind != _RowKind.empty) {
      rows.add(const _Row(_RowKind.pet));
    }
    final String partial = _loop?.partial ?? '';
    if (partial.isNotEmpty) {
      rows.add(_Row(_RowKind.streaming, text: partial));
    } else if (_running) {
      rows.add(const _Row(_RowKind.thinking));
    }
    if (rows.isEmpty) rows.add(const _Row(_RowKind.empty));
    return rows;
  }

  /// 一行长什么样。列表只叫它要看得见的那几行，翻到哪儿画到哪儿。
  Widget _row(_Row r, Map<String, String> outputs, String runningId) {
    switch (r.kind) {
      case _RowKind.user:
        return _userTurn(r.message!);
      case _RowKind.answer:
        // 这条回答花了多少 token，就写在它下面。
        final LlmUsage used = r.message?.usage ?? const LlmUsage();
        // 模型那一行报错的时候，就在它下面给一个回退：退回去改两个字再发。
        final bool broke = r.message?.role == LlmRole.assistant &&
            r.text.startsWith('模型请求失败');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _answer(r.text, bottom: used.total > 0 || broke ? 5 : 18),
            if (used.total > 0) _usageLine(used),
            if (broke) _rollbackLine(),
          ],
        );
      case _RowKind.tool:
        final LlmUsage spent = r.message?.usage ?? const LlmUsage();
        // 既有回答又有工具时，token 挂在回答那边，这里不重复一遍。
        final bool show = spent.total > 0 && r.message!.text.trim().isEmpty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _toolTurn(r.message!.calls, outputs, runningId),
            if (show) _usageLine(spent),
          ],
        );
      case _RowKind.streaming:
        return _answer(r.text, streaming: true);
      case _RowKind.trim:
        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Text(r.text,
              style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6)),
        );
      case _RowKind.summary:
        return _summaryCard(r.message!.text.substring(kCompactMark.length).trim());
      case _RowKind.plan:
        return _finishedPlan();
      case _RowKind.pet:
        return _sleepingCat();
      case _RowKind.thinking:
        return _ThinkingRow(
          phase: _loop?.phase ?? AgentPhase.thinking,
          poemOn: widget.services.settings.value.poemOn,
          poemEvery: widget.services.settings.value.poemEvery,
        );
      case _RowKind.empty:
        return _empty();
    }
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
            child: Text('❯',
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

  /// 一轮里带的照片：一张就大一点，几张就排成方阵，点开看大图。
  Widget _photoStrip(List<String> photos) {
    final bool single = photos.length == 1;
    const double small = 96;
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
                width: single ? 220 : small,
                height: single ? 165 : small,
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
      return Center(
        child: Text('读不出这张图',
            style: TextStyle(fontSize: 11, color: C.grey2)),
      );
    }
    return Image.memory(
      bytes,
      fit: fit,
      gaplessPlayback: true,
      errorBuilder: (BuildContext ctx, Object error, StackTrace? stack) =>
          Center(
        child: Text('读不出这张图',
            style: TextStyle(fontSize: 11, color: C.grey2)),
      ),
    );
  }

  /// 点开一张：全屏、可拖动放大，点一下退出。
  void _openPhoto(List<String> photos, int start) {
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: C.scrim,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b) =>
          _PhotoViewer(photos: photos, start: start),
      transitionsBuilder:
          (BuildContext ctx, Animation<double> a, Animation<double> b, Widget child) =>
              FadeTransition(opacity: a, child: child),
    ));
  }

  /// 一条回答下面那行小字：进多少、出多少、命中多少。
  Widget _usageLine(LlmUsage usage) {
    final String hit =
        usage.cached > 0 ? ' · 命中 ${(usage.cacheHitRate * 100).round()}%' : '';
    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: 16),
      child: Text(
        '${_fmtTokens(usage.prompt)} 进 · ${_fmtTokens(usage.completion)} 出$hit',
        style: C.monoSmall.copyWith(fontSize: 10.5, color: C.grey2),
      ),
    );
  }

  /// 报错那一轮下面的那一行：回退一句，再发一遍。
  Widget _rollbackLine() {
    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: 16),
      child: GestureDetector(
        onTap: _canRollback ? () => _rollback() : null,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.undo_rounded, size: 14, color: _canRollback ? C.blue : C.grey2),
            const SizedBox(width: 5),
            Text(
              _canRollback ? '回退这一步，改一改再发' : '跑着的时候不能退',
              style: TextStyle(
                fontSize: 12,
                color: _canRollback ? C.blue : C.grey2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _answer(String text, {bool streaming = false, double bottom = 18}) {
    final List<String> out = streaming
        ? const <String>[]
        : localOutputs(widget.services.files, text);
    return Padding(
      padding: EdgeInsets.only(left: 34, bottom: streaming ? 6 : bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MdText(
            text: text,
            streaming: streaming,
            base: C.answer.copyWith(fontSize: widget.services.settings.value.answerFont),
          ),
          if (out.isNotEmpty)
            OutputPreview(
              files: widget.services.files,
              paths: out,
              onMore: _openTempFiles,
            ),
        ],
      ),
    );
  }

  Widget _toolTurn(List<LlmToolCall> calls, Map<String, String> outputs, String runningId) {
    // 这一组工具写出来的图和网页，就在它们下面露一眼。
    final StringBuffer said = StringBuffer();
    for (final LlmToolCall c in calls) {
      final String? out = outputs[c.id];
      if (out != null) said.writeln(out);
    }
    final List<String> shown = localOutputs(widget.services.files, said.toString());
    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ToolRunGroup(calls: calls, outputs: outputs, runningId: runningId),
          if (shown.isNotEmpty)
            OutputPreview(
              files: widget.services.files,
              paths: shown,
              onMore: _openTempFiles,
            ),
        ],
      ),
    );
  }

  /// 做完的那张计划：已经落进记录里，跟对话一起滚。
  Widget _finishedPlan() {
    final WorkPlan? plan = widget.conversation.plan;
    if (plan == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: PlanBar(plan: plan, pad: EdgeInsets.zero),
    );
  }

  /// 没活干的时候，记录末尾右边躺一只睡着的小猫。
  Widget _sleepingCat() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Align(
        alignment: Alignment.centerRight,
        child: PetAvatar(size: 64, mood: PetMood.sleeping),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PetAvatar(
            size: 124,
            mood: petMoodNow(
              running: widget.hub.runningCount > 0,
              waiting: widget.hub.waitingOnes.isNotEmpty,
              greeting: true,
            ),
            showState: true,
          ),
          const SizedBox(height: 16),
          const Text('说说要做什么',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 10),
          Text('例如：看磁盘使用率，清掉 nginx 的老日志。', style: C.answer),
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
                  ? '这个对话可以操作全部主机，用哪一台由它选。'
                  : '这个对话只操作一台主机，记忆也保存在这台机器名下。',
              style: TextStyle(fontSize: 12.5, height: 1.6, color: C.grey),
            ),
          ),
        ],
      ),
    );
  }

  /// 这一场现在用哪套配置。
  ModelProfile get _profile =>
      profileOf(widget.services.settings.value, widget.conversation.profileId);

  /// 顶栏那颗：现在用的是哪套模型，点一下换一套。
  Widget _modelPill() {
    final ModelProfile p = _profile;
    final bool pinned = widget.conversation.profileId.isNotEmpty;
    final bool wide = MediaQuery.sizeOf(context).width >= 420;
    return GestureDetector(
      onTap: _pickModel,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 24,
        padding: EdgeInsets.symmetric(horizontal: wide ? 8 : 6),
        decoration: BoxDecoration(
          color: pinned ? C.blueSoft : C.paper2,
          borderRadius: BorderRadius.circular(C.radiusSmall),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.memory, size: 11, color: pinned ? C.blue : C.grey),
            if (wide) ...<Widget>[
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 96),
                child: Text(
                  p.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: C.monoSmall.copyWith(
                    fontSize: 10,
                    height: 1.2,
                    color: pinned ? C.blue : C.grey,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 换这场对话的模型配置：只改这一场，设置里的默认不动。
  Future<void> _pickModel() async {
    final AppSettings s = widget.services.settings.value;
    final String current = widget.conversation.profileId;
    final String? pick = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => SheetCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('这场对话用哪套模型',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: C.ink)),
            const SizedBox(height: 3),
            Text('换过去之后，新消息按那一套的提示词和参数走，记录不动。', style: C.monoSmall),
            const SizedBox(height: 12),
            for (final ModelProfile p in s.profiles) ...<Widget>[
              _modelRow(p, current, s.activeProfile),
              const SizedBox(height: 8),
            ],
            _sheetRow(
              Icons.link,
              '跟设置走',
              '设置里换成哪套，这场就用哪套',
              current.isNotEmpty,
              () => Navigator.of(ctx).pop('__follow__'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || pick == null) return;
    final Conversation c = widget.conversation;
    c.profileId = pick == '__follow__' ? '' : pick;
    await widget.services.persist(c);
    final LiveSession? live = _live;
    if (live != null) {
      // 提示词也跟着换：下一句就按新配置那份执行。
      live.loop.systemPrompt = promptFor(widget.services.settings, c);
    }
    if (!mounted) return;
    setState(() {});
    // 换了一套模型就是另一个账户，余额重新问一句。
    unawaited(_balance.refresh(_profile, force: true));
    _toast(c.profileId.isEmpty
        ? '这场对话跟设置走。'
        : '这场对话换成 ${_profile.label}，下一句就按它走。');
  }

  Widget _modelRow(ModelProfile p, String current, String defaultId) {
    final bool on = current.isEmpty ? p.id == defaultId : p.id == current;
    final String note = <String>[
      if (p.model.trim().isNotEmpty) p.model.trim(),
      if (p.id == defaultId) '设置里的默认',
      if (!p.complete) '还没填完',
    ].join(' · ');
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(p.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 10, 11),
        decoration: BoxDecoration(
          color: on ? C.blueSoft : C.paper2,
          borderRadius: BorderRadius.circular(C.radiusSmall),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.memory,
                size: 18, color: on ? C.blue : C.grey),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(p.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: on ? C.blue : C.ink)),
                  if (note.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(note, maxLines: 1, overflow: TextOverflow.ellipsis, style: C.monoSmall),
                  ],
                ],
              ),
            ),
            if (on) Icon(Icons.check, size: 16, color: C.blue),
          ],
        ),
      ),
    );
  }

  /// 标题两行：名字在上，跟谁在聊在下。名字太长就收成省略号，不推挤右边。
  Widget _heading() {    return Column(
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
        Text(
          widget.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: C.monoSmall,
        ),
      ],
    );
  }

  /// 标题右边那一小牌：跑着就写第几步，闲着就写这一场花了多少。
  Widget _statusPill(AgentLoop? loop) {
    if (loop == null) return const SizedBox.shrink();
    final bool running = _running;
    // 看最近这一次请求命中多少：累计值把冷启动那一轮也算进去了，永远偏低。
    final double hit =
        loop.lastCacheHitRate > 0 ? loop.lastCacheHitRate : loop.cacheHitRate;
    final bool wide = MediaQuery.sizeOf(context).width >= 380;
    final String text = running
        ? '${loop.step}/${loop.maxSteps}${wide && hit > 0 ? ' · ${(hit * 100).round()}%' : ''}'
        : '${_fmtTokens(loop.tokens)} tok${wide && hit > 0 ? ' · 命中 ${(hit * 100).round()}%' : ''}';
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: running ? C.blueSoft : C.paper2,
        borderRadius: BorderRadius.circular(C.radiusSmall),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (running) ...<Widget>[
            SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(strokeWidth: 1.4, color: C.blue),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: C.monoSmall.copyWith(
              fontSize: 10,
              height: 1.2,
              color: running ? C.blue : C.grey,
            ),
          ),
        ],
      ),
    );
  }

  /// 产物多的时候，剩下那些在临时文件页里看。
  void _openTempFiles() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => TempFilesPage(
          files: widget.services.files,
          hosts: widget.services.hosts,
          pool: widget.services.pool,
        ),
      ),
    );
  }

  /// 这一路模型叫什么工具、花了多久、回来什么，都在这一页。
  void _openTrace() {
    Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (BuildContext ctx) => TracePage(
        file: widget.services.conversations.journalOf(widget.conversation),
        live: _running,
      ),
    ));
  }

  static String _fmtTokens(int n) {
    if (n < 1000) return '$n';
    final double k = n / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0)}k';
  }

  @override
  Widget build(BuildContext context) {
    final AgentLoop? loop = _loop;
    final List<_Row> rows = _rows();
    final Map<String, String> outputs = _outputs();
    final String runningId = _runningId(outputs);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Column(
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.fromLTRB(6, 0, 8, 0),
          decoration: BoxDecoration(
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
          ),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: widget.onOpenSidebar ?? widget.onBack,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 36,
                  height: 56,
                  child: Icon(
                    widget.onOpenSidebar == null ? Icons.arrow_back : Icons.menu,
                    size: 19,
                    color: C.ink,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Expanded(child: _heading()),
              _modelPill(),
              const SizedBox(width: 4),
              _statusPill(loop),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: _openTrace,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 34,
                  height: 56,
                  child: Icon(Icons.timeline, size: 17, color: C.grey),
                ),
              ),
              GestureDetector(
                onTap: _canRollback ? () => _rollback() : null,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 34,
                  height: 56,
                  child: Icon(
                    Icons.undo_rounded,
                    size: 18,
                    color: _canRollback ? C.ink : C.grey.withValues(alpha: 0.45),
                  ),
                ),
              ),
              GestureDetector(
                onTap: _moreSheet,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 34,
                  height: 56,
                  child: Icon(Icons.more_horiz, size: 18, color: C.grey),
                ),
              ),
            ],
          ),
        ),
        if (widget.conversation.plan != null && !widget.conversation.plan!.finished)
          PlanBar(plan: widget.conversation.plan!),
        Expanded(
          child: Stack(
            children: <Widget>[
              // 对话里的字都能选中，长按就能复制。
              Positioned.fill(
                child: SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
                    // 按需建行：打开长对话只排看得见的那几十行，键盘弹起、
                    // 输入框亮一下也不会把整份记录重排一遍。
                    cacheExtent: 800,
                    itemCount: rows.length,
                    itemBuilder: (BuildContext ctx, int i) =>
                        _row(rows[i], outputs, runningId),
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
                      child: Icon(Icons.arrow_downward, size: 17, color: C.blue),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (_pending != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: FadeSlideIn(
              lift: 6,
              duration: const Duration(milliseconds: 220),
              child: ConstrainedBox(
                // 卡在看得到的区域里长，内容再长也不把「批准」顶出去。
                constraints: BoxConstraints(maxHeight: _pinnedMax),
                child: ApprovalCard(
                  request: _pending!,
                  onDecide: _decide,
                  onAllowKind: _allowKind,
                  onAllowAll: _allowAll,
                  kindLabel: _kind,
                ),
              ),
            ),
          ),
        if (_live?.pendingAsk != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: FadeSlideIn(
              lift: 6,
              duration: const Duration(milliseconds: 220),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _pinnedMax),
                child: _AskCard(
                  request: _live!.pendingAsk!,
                  onAnswer: (String text) => _live?.answerAsk(text),
                ),
              ),
            ),
          ),
        if (_attachNames.isNotEmpty) _attachRow(),
        if (widget.conversation.costCny > 0 || BalanceStore.supports(_profile.baseUrl))
          _costLine(),
        _composer(loop),
      ],
          ),
        ),
        if (_greetingOn) _greetingRail(),
      ],
    );
  }

  /// 宽屏才在右边写问候语：窄屏上那一栏会把正文挤成一条。
  bool get _greetingOn =>
      MediaQuery.sizeOf(context).width >= 1000 &&
      widget.services.settings.value.greetOn;

  /// 右边那几行：一句问候，用 DeepSeek 的时候再加一段峰谷提示。
  Widget _greetingRail() {
    final AppSettings s = widget.services.settings.value;
    final ModelProfile p = _profile;
    final Greeting greeting = greetingFor(
      at: DateTime.now(),
      model: p.model,
      peakHint: s.greetPeak,
      clock: s.deepSeekClock(),
    );
    return Container(
      width: 212,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
      decoration: BoxDecoration(
        color: C.card,
        border: Border(left: BorderSide(color: C.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(greeting.line,
              style: TextStyle(fontSize: 13, height: 1.75, color: C.ink)),
          const SizedBox(height: 14),
          if (greeting.hasPeak) ...<Widget>[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
              decoration: BoxDecoration(
                color: C.paper2,
                borderRadius: BorderRadius.circular(C.radiusSmall),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(greeting.peak == true ? '高峰' : '谷时',
                      style: C.monoSmall.copyWith(
                        fontSize: 10.5,
                        color: greeting.peak == true ? C.ink : C.blue,
                        letterSpacing: 1,
                      )),
                  const SizedBox(height: 5),
                  Text(greeting.peakLine,
                      style: TextStyle(fontSize: 11.5, height: 1.65, color: C.ink)),
                  if (greeting.hint.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(greeting.hint,
                        style: TextStyle(fontSize: 11, height: 1.65, color: C.grey)),
                  ],
                ],
              ),
            ),
          ],
          const Spacer(),
          Text(p.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: C.monoSmall.copyWith(fontSize: 10.5, color: C.grey2)),
        ],
      ),
    );
  }

  /// 这一场花了多少：输入、输出、合计，一行小字放在输入框上面。
  ///
  /// 价按这场对话钉住的那套配置算：手填的价在先，没填就用内置价目表。
  /// DeepSeek 再标一句现在是不是谷时。
  /// 服务商给了余额接口的话，右边再写一句账上还剩多少，点一下重问一次。
  Widget _costLine() {
    final ModelProfile p = _profile;
    final AccountBalance? money = _balance.value;
    final bool canAsk = BalanceStore.supports(p.baseUrl);
    final PriceQuote quote = quotePrice(manual: p.price, model: p.model);
    String tail = quote.known ? quote.sourceLabel : '';
    if (quote.peakValley) {
      final PeakState now = widget.services.settings.value.deepSeekClock().state(DateTime.now());
      tail = quote.known
          ? '${quote.sourceLabel} · ${now.peak ? '高峰价' : '谷时半价'}'
          : '谷时半价';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 6),
      child: Row(
        children: <Widget>[
          if (widget.conversation.costCny > 0)
            Text('本次会话 ${moneyText(widget.conversation.costCny)}',
                style: C.monoSmall.copyWith(fontSize: 10.5, color: C.grey)),
          const Spacer(),
          if (tail.isNotEmpty)
            Text(tail, style: C.monoSmall.copyWith(fontSize: 10.5, color: C.grey2)),
          if (canAsk) ...<Widget>[
            if (tail.isNotEmpty)
              Text(' · ', style: C.monoSmall.copyWith(fontSize: 10.5, color: C.grey2)),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => unawaited(_balance.refresh(p, force: true)),
              child: Text(
                money == null
                    ? (_balance.loading ? '余额 …' : '余额 --')
                    : '余额 ${money.text}',
                style: C.monoSmall.copyWith(fontSize: 10.5, color: C.grey),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 输入条上面那一条：带进来的东西排成一排小方块，图片给缩略图，文本给图标。
  Widget _attachRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          for (int i = 0; i < _attachNames.length; i += 1) _attachTile(i),
        ],
      ),
    );
  }

  Widget _attachTile(int i) {
    final String name = _attachNames[i];
    final String photo = i < _attachPhotos.length ? _attachPhotos[i] : '';
    final bool image = photo.isNotEmpty;
    return SizedBox(
      width: 62,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 62,
            height: 62,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Container(
                  width: 62,
                  height: 62,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: C.paper2,
                    borderRadius: BorderRadius.circular(C.radiusSmall),
                    border: Border.all(color: C.rule2),
                  ),
                  child: image
                      ? _photoImage(photo, fit: BoxFit.cover)
                      : Center(
                          child: Icon(_attachIcon(name), size: 22, color: C.grey),
                        ),
                ),
                Positioned(
                  right: -6,
                  top: -6,
                  child: GestureDetector(
                    onTap: () => _dropAttach(i),
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: C.paper, width: 1.5),
                      ),
                      child: Icon(Icons.close, size: 11, color: C.onAccent),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: C.monoSmall.copyWith(fontSize: 9.5, color: C.grey),
          ),
        ],
      ),
    );
  }

  /// 去掉一个附件。图片按内容从 `_images` 里拿，不按下标，
  /// 否则前面夹一个文本文件，后面那张图就会被错删。
  void _dropAttach(int i) {
    final String photo = i < _attachPhotos.length ? _attachPhotos[i] : '';
    setState(() {
      _attachNames.removeAt(i);
      if (photo.isNotEmpty) _images.remove(photo);
      if (i < _attachPhotos.length) _attachPhotos.removeAt(i);
    });
  }

  IconData _attachIcon(String name) {
    final String lower = name.toLowerCase();
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) return Icons.article_outlined;
    if (lower.endsWith('.docx')) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  /// 输入条。框跟着焦点亮，左边加东西，右边发或者停，写完没发可以一键清掉。
  Widget _composer(AgentLoop? loop) {
    final bool running = _running;
    final bool canType = loop != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(C.radius),
          border: Border.all(color: _typing ? C.blue : C.rule),
          boxShadow: C.softShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            _composerKey(
              Icons.add_circle_outline,
              canType ? _attachSheet : null,
              size: 21,
            ),
            Padding(
              padding: EdgeInsets.only(left: 2, bottom: 9),
              child: Text('❯', style: TextStyle(fontSize: 14, color: C.blue)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _input,
                focusNode: _focus,
                enabled: canType,
                style: const TextStyle(fontSize: 14.5, height: 1.5),
                minLines: 1,
                maxLines: 5,
                // 跑的时候回车只管换行：先把下一句写下来，跑完再发。
                textInputAction:
                    running ? TextInputAction.newline : TextInputAction.send,
                onSubmitted: (_) {
                  if (!running) _send();
                },
                decoration: InputDecoration(
                  hintText: running ? '这一轮还在跑，可以先写下一句' : '交给它一件事',
                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                ),
              ),
            ),
            const SizedBox(width: 4),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _input,
              builder: (BuildContext ctx, TextEditingValue value, Widget? child) {
                final bool typed = value.text.trim().isNotEmpty || _images.isNotEmpty;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (value.text.isNotEmpty && !running)
                      _composerKey(Icons.close, _input.clear, size: 16),
                    _sendKey(running: running, canType: canType, typed: typed),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 输入条里的一个图标键：高度跟发送键对齐，文字一长也不会跑。
  Widget _composerKey(IconData icon, VoidCallback? onTap, {double size = 18}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 30,
        height: 38,
        child: Icon(icon, size: size, color: onTap == null ? C.rule2 : C.grey),
      ),
    );
  }

  /// 右边那一颗：平时是发，跑的时候是停。按下去会缩一点。
  Widget _sendKey({
    required bool running,
    required bool canType,
    required bool typed,
  }) {
    final bool on = running || (canType && typed);
    return PressScale(
      onTap: !on ? null : (running ? _stop : _send),
      scale: 0.92,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? C.blue : C.rule,
          borderRadius: BorderRadius.circular(C.radiusSmall),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: running
              ? Container(
                  key: const ValueKey<String>('stop'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: C.onAccent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : Icon(
                  Icons.arrow_upward,
                  key: ValueKey<String>('send'),
                  size: 19,
                  color: C.onAccent,
                ),
        ),
      ),
    );
  }
}

/// 一行的身份与内容。不拿 Widget 当缓存，状态一变也不必把整份记录重造。
enum _RowKind { trim, summary, plan, user, answer, tool, streaming, thinking, pet, empty }

class _Row {
  const _Row(this.kind, {this.message, this.text = ''});

  final _RowKind kind;
  final LlmMessage? message;
  final String text;
}

/// 压缩出来的那一段：默认收三行，想看全文再展开。
class _SummaryCard extends StatefulWidget {
  const _SummaryCard({required this.text});

  final String text;

  @override
  State<_SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<_SummaryCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: C.paper2,
        borderRadius: BorderRadius.circular(C.radiusSmall),
        border: Border.all(color: C.rule),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: <Widget>[
                Icon(Icons.compress, size: 13, color: C.grey),
                const SizedBox(width: 6),
                Text('更早的对话已压缩',
                    style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.4)),
                const Spacer(),
                Icon(_open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 16, color: C.grey2),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            widget.text,
            maxLines: _open ? null : 3,
            overflow: _open ? TextOverflow.clip : TextOverflow.ellipsis,
            style: C.answer.copyWith(fontSize: 12.5, color: C.grey),
          ),
        ],
      ),
    );
  }
}

/// 等待时读的那首古诗：库里随机抽，隔一会儿换一首，不连着重复。

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
      border: C.approveBorder,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          // 问题再长也只在这块里滚，输入框和按钮留着。
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: C.card,
                                borderRadius: BorderRadius.circular(C.radiusSmall),
                                border: Border.all(color: C.blue),
                              ),
                              child: Text(option,
                                  style: TextStyle(fontSize: 12, color: C.blue)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
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
  const _ThinkingRow({
    required this.phase,
    this.poemOn = true,
    this.poemEvery = kPoemEveryDefault,
  });

  final AgentPhase phase;

  /// 这一行右边读不读诗。
  final bool poemOn;

  /// 隔多少秒换一首。
  final int poemEvery;

  @override
  State<_ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<_ThinkingRow> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();
  Timer? _tick;
  Timer? _poemTimer;
  int _seconds = 0;

  /// 这一首和它的轮子。
  final PoemWheel _wheel = PoemWheel();
  Poem? _poem;

  @override
  void initState() {
    super.initState();
    if (widget.poemOn) _poem = _wheel.next();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds += 1);
    });
    if (widget.poemOn) {
      _poemTimer = Timer.periodic(
        Duration(seconds: clampPoemEvery(widget.poemEvery)),
        (_) {
          if (!mounted) return;
          setState(() => _poem = _wheel.next());
        },
      );
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _tick?.cancel();
    _poemTimer?.cancel();
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

  /// 四步各配一张：在等模型、在跑命令、在等你、在收尾。
  PetMood get _mood {
    switch (widget.phase) {
      case AgentPhase.thinking:
        return PetMood.loading;
      case AgentPhase.acting:
        return PetMood.working;
      case AgentPhase.waiting:
        return PetMood.thinking;
      case AgentPhase.idle:
        return PetMood.happy;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: 14),
      child: Row(
        children: <Widget>[
          PetAvatar(size: 30, mood: _mood, showState: false),
          const SizedBox(width: 8),
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
                          decoration: BoxDecoration(color: C.blue, shape: BoxShape.circle),
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
          const SizedBox(width: 10),
          if (widget.poemOn && _poem != null)
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.swap,
                child: _poemBlock(_poem!),
              ),
            )
          else
            const Expanded(child: SizedBox.shrink()),
        ],
      ),
    );
  }

  /// 一首诗：题目与作者弱化着写在上头，正文分两行，读得清比什么都要紧。
  Widget _poemBlock(Poem poem) {
    TextStyle style = TextStyle(
      fontSize: 11,
      height: 1.5,
      color: C.grey2,
      letterSpacing: 0.4,
    );
    return Column(
      key: ValueKey<String>(poem.line),
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(poem.byline,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 9, height: 1.3, color: C.grey2)),
        Text(poem.head, textAlign: TextAlign.right, style: style),
        if (poem.tail.isNotEmpty)
          Text(poem.tail, textAlign: TextAlign.right, style: style),
      ],
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
                        ? Text('读不出这张图',
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
                    style: TextStyle(
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
