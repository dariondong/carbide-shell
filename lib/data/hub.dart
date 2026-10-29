import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/agent.dart';
import '../core/compact.dart';
import '../core/conversation.dart';
import '../core/pricing.dart';
import '../core/usage.dart';
import '../core/llm_base.dart';
import '../core/models.dart';
import '../core/tools.dart';
import '../services.dart';
import '../tools/ask_tool.dart';
import 'activity.dart';
import 'llm_settings.dart';
import 'settings.dart';

/// 一个对话在跑的时候的全部状态。
///
/// 跑的内容不在页面里，所以关掉这一页、切到别的对话去，它照样往下跑；
/// 回到这个对话时看到的是同一个循环、同一段正在长出来的回答。
class LiveSession {
  LiveSession({required this.conversation, required this.session}) {
    session.loop.approver = _LiveApprover(this);
    session.loop.onChanged = () => hub?.touch(this);
    _wireAsk();
  }

  /// 把 ask 工具接到这个对话上：模型提问时等人回答，回答再喂回去。
  void _wireAsk() {
    final Tool? tool = session.loop.registry.byName('ask');
    if (tool is AskTool) tool.resolver = askUser;
  }

  final Conversation conversation;
  final AgentSession session;

  /// 由 [SessionHub.open] 挂上，循环里每次变化都要经它通知界面。
  SessionHub? hub;

  AgentLoop get loop => session.loop;

  bool running = false;

  /// 停这一轮用的令牌。
  CancelToken? cancel;

  /// 正在等用户点头的那一条。不在这页时也可以等着。
  ApprovalRequest? pending;
  String pendingKind = '';
  Completer<bool>? _waiter;

  /// 模型正在问的问题，等用户回答。
  AskRequest? pendingAsk;
  Completer<String>? _askWaiter;

  DateTime lastNote = DateTime.fromMillisecondsSinceEpoch(0);
  String lastNoteText = '';

  bool get waiting => pending != null || pendingAsk != null;

  /// ask 工具在这里停下来等人。页面关着也照样等着，回来再答。
  Future<String> askUser(AskRequest request) {
    pendingAsk = request;
    final Completer<String> waiter = Completer<String>();
    _askWaiter = waiter;
    hub?.changed();
    return waiter.future;
  }

  /// 用户答了。
  void answerAsk(String text) {
    final Completer<String>? waiter = _askWaiter;
    pendingAsk = null;
    _askWaiter = null;
    hub?.changed();
    if (waiter != null && !waiter.isCompleted) waiter.complete(text);
  }

  /// 循环要人确认时走这里。这个对话记住过这一类的就自己放行。
  Future<bool> ask(ApprovalRequest request) {
    final String kind = approvalKind(request.call);
    if (conversation.allowsKind(kind)) return Future<bool>.value(true);
    pending = request;
    pendingKind = kind;
    final Completer<bool> waiter = Completer<bool>();
    _waiter = waiter;
    hub?.changed();
    return waiter.future;
  }

  void decide(bool allow) {
    final Completer<bool>? waiter = _waiter;
    pending = null;
    _waiter = null;
    hub?.changed();
    if (waiter != null && !waiter.isCompleted) waiter.complete(allow);
  }
}

class _LiveApprover implements Approver {
  _LiveApprover(this.live);

  final LiveSession live;

  @override
  Future<bool> confirm(ApprovalRequest request) => live.ask(request);
}

/// 所有活着对话的托管处：谁在建、谁在跑、谁在等确认。
///
/// 一个对话只有一个循环，所以从列表点进去再退出，不会出现两份同时在改同一段记录。
class SessionHub extends ChangeNotifier {
  SessionHub({required this.services, required this.board});

  final AppServices services;
  final ActivityBoard board;

  final Map<String, LiveSession> _live = <String, LiveSession>{};

  LiveSession? byId(String id) => _live[id];

  bool isRunning(String id) => _live[id]?.running ?? false;

  bool isWaiting(String id) => _live[id]?.waiting ?? false;

  /// 谁在跑、谁在等确认的粗签名。界面外壳只在这一串变了的时候重画，
  /// 正文一个字一个字冒出来不用惊动整个页面。
  String get signature {
    final List<String> parts = <String>[];
    for (final LiveSession s in _live.values) {
      if (s.running) parts.add('r:${s.conversation.id}');
      if (s.waiting) parts.add('w:${s.conversation.id}');
    }
    parts.sort();
    return parts.join(',');
  }

  int get runningCount {
    int n = 0;
    for (final LiveSession s in _live.values) {
      if (s.running) n += 1;
    }
    return n;
  }

  /// 等确认的对话，界面上要点出来。
  List<LiveSession> get waitingOnes =>
      _live.values.where((LiveSession s) => s.waiting).toList();

  /// 拿到这个对话的活会话，没有就现建一个。
  Future<LiveSession> open(Conversation conversation) async {
    final LiveSession? have = _live[conversation.id];
    if (have != null) return have;
    final AgentSession session = await services.sessionFor(conversation);
    final LiveSession live = LiveSession(conversation: conversation, session: session)
      ..hub = this;
    _live[conversation.id] = live;
    return live;
  }

  /// 通知里写的那句：这个对话还在跑就先排在后面，跑完接着发。
  final Map<String, List<String>> _queued = <String, List<String>>{};

  void enqueue(String conversationId, String text) {
    final String body = text.trim();
    if (body.isEmpty) return;
    _queued.putIfAbsent(conversationId, () => <String>[]).add(body);
    changed();
  }

  /// 排着还没发出去的几句，界面上按它提示一下。
  List<String> queued(String conversationId) =>
      List<String>.unmodifiable(_queued[conversationId] ?? const <String>[]);

  /// 这一轮跑完，排着的那句接着发。
  void _drain(LiveSession live) {
    final List<String>? queue = _queued[live.conversation.id];
    if (queue == null || queue.isEmpty) return;
    final String next = queue.removeAt(0);
    if (queue.isEmpty) _queued.remove(live.conversation.id);
    unawaited(send(live, next));
  }

  /// 让它跑一轮。同一个对话不会叠两轮。
  Future<String> send(
    LiveSession live,
    String text, {
    List<String> images = const <String>[],
  }) async {
    if (live.running) return '';
    final AgentLoop loop = live.loop;
    live.running = true;
    live.cancel = CancelToken();
    live.lastNote = DateTime.fromMillisecondsSinceEpoch(0);
    live.lastNoteText = '';
    loop.maxSteps = services.settings.value.maxSteps;
    loop.extraSystem = services.settings.value.extraPrompt;
    // 设置里的提示词改了，下一轮就用新的；对话自己那份照旧优先。
    loop.systemPrompt = promptFor(services.settings, live.conversation);
    // 刚打开或关掉的扩展，这一轮就按新的清单来。
    services.syncTools(live.session);
    final int wasPrompt = loop.promptTokens;
    final int wasTokens = loop.tokens;
    final int wasCached = loop.cachedTokens;
    changed();
    // 记录长得太离谱就先压一次，不然这一轮要把几十万字重新发一遍。
    await _maybeCompact(live);
    board.note('c:${live.conversation.id}', '${live.conversation.title} · 开跑');
    try {
      return await loop.send(text, cancel: live.cancel, images: images);
    } finally {
      live.running = false;
      live.cancel = null;
      live.pending = null;
      live.pendingAsk = null;
      live.conversation.tokensUsed = loop.tokens;
      await services.persist(live.conversation);
      await _recordUsage(
        live,
        wasPrompt: wasPrompt,
        wasTokens: wasTokens,
        wasCached: wasCached,
      );
      board.done('c:${live.conversation.id}',
          summary: '${live.conversation.title} · ${summaryOf(live)}');
      changed();
      _drain(live);
    }
  }

  /// 这一轮花了多少 token 记进账本。多步的算一轮。
  Future<void> _recordUsage(
    LiveSession live, {
    required int wasPrompt,
    required int wasTokens,
    required int wasCached,
  }) async {
    final AgentLoop loop = live.loop;
    final int prompt = loop.promptTokens - wasPrompt;
    final int completion = (loop.tokens - wasTokens) - prompt;
    final int cached = loop.cachedTokens - wasCached;
    if (prompt <= 0 && completion <= 0) return;
    // 这一轮用的是这场对话钉住的那套配置，价钱也按它的来。
    final ModelProfile profile =
        profileOf(services.settings.value, live.conversation.profileId);
    final PriceQuote quote = quotePrice(manual: profile.price, model: profile.model);
    final DateTime now = DateTime.now();
    final int fixedPrompt = prompt < 0 ? 0 : prompt;
    final int fixedCompletion = completion < 0 ? 0 : completion;
    final int fixedCached = cached < 0 ? 0 : cached;
    final double factor = quote.peakValley
        ? peakFactor(
            peakValley: true, at: now, clock: services.settings.value.deepSeekClock())
        : 1;
    final CostSplit cost = quote.known
        ? costSplitOf(
            prompt: fixedPrompt,
            completion: fixedCompletion,
            cached: fixedCached,
            price: quote.price!,
            factor: factor,
          )
        : const CostSplit();
    await services.usage.record(UsageEntry(
      at: now,
      model: profile.model,
      prompt: fixedPrompt,
      completion: fixedCompletion,
      cached: fixedCached,
      costIn: cost.promptTotal,
      costOut: cost.output,
      conversationId: live.conversation.id,
    ));
    if (cost.total > 0) {
      live.conversation.costCny += cost.total;
      await services.persist(live.conversation);
    }
  }

  /// 停一轮：正在等确认的也一起放掉。
  void stop(LiveSession live) {
    live.cancel?.cancel();
    live.decide(false);
  }

  /// 记录长到这个份上就该收了。按上下文的倍数算，下限十几万字，
  /// 免得短对话也被拉着压一次。
  static const int kAutoCompactFloor = 120000;

  Future<void> _maybeCompact(LiveSession live) async {
    if (!services.settings.value.autoCompact) return;
    int total = 0;
    for (final LlmMessage m in live.conversation.messages) {
      total += messageWeight(m);
    }
    final int limit = (live.loop.maxContextChars * 3).clamp(kAutoCompactFloor, 900000);
    if (total <= limit) return;
    if (compactCut(live.conversation.messages) <= 0) return;
    await _compact(live);
  }

  /// 把前面那一段收成一段摘要。跑着的时候不动它，模型不回话就什么都不改。
  /// 返回摘要本身，空串表示没压。
  Future<String> compact(LiveSession live) async {
    if (live.running) return '';
    live.running = true;
    live.cancel = CancelToken();
    changed();
    try {
      return await _compact(live);
    } finally {
      live.running = false;
      live.cancel = null;
      changed();
    }
  }

  Future<String> _compact(LiveSession live) async {
    final Conversation c = live.conversation;
    final int cut = compactCut(c.messages);
    if (cut <= 0) return '';
    final String ask = compactPrompt(c.messages.sublist(0, cut));
    LlmReply reply;
    try {
      reply = await live.loop.llm.chat(
        system: kCompactSystem,
        messages: <LlmMessage>[LlmMessage.user(ask)],
        tools: const <ToolSpec>[],
      );
    } catch (_) {
      return '';
    }
    final String text = reply.text.trim();
    if (text.isEmpty) return '';
    c.messages.removeRange(0, cut);
    c.messages.insert(0, LlmMessage.assistant('$kCompactMark\n$text'));
    c.dropped += cut;
    // 收掉的那一段连同它们占的位置一起去掉，做完的那张计划仍停在它自己那一行。
    c.planAnchor = (c.planAnchor - cut + 1).clamp(0, c.messages.length).toInt();
    live.loop.onHistoryChanged();
    await services.persist(c);
    return text;
  }

  /// 对话被删掉了，把它手里的东西也收走。
  void forget(String id) {
    _live.remove(id);
    board.done('c:$id');
    changed();
  }

  void changed() => notifyListeners();

  /// 循环每动一下都会调这里：更新通知上那句话，同时让界面重画。
  void touch(LiveSession live) {
    note(live);
    notifyListeners();
  }

  /// 通知上写「第 3/12 步 · 执行命令」。1.2 秒一次，字没变就不写。
  void note(LiveSession live) {
    if (!live.running) return;
    final DateTime now = DateTime.now();
    if (now.difference(live.lastNote).inMilliseconds < 1200) return;
    live.lastNote = now;
    final String where = switch (live.loop.phase) {
      AgentPhase.thinking => '等模型回话',
      AgentPhase.acting => '执行命令',
      AgentPhase.waiting => '等你确认',
      AgentPhase.idle => '收尾',
    };
    final String text =
        '${live.conversation.title} · 第 ${live.loop.step}/${live.loop.maxSteps} 步 · $where';
    if (text == live.lastNoteText) return;
    live.lastNoteText = text;
    board.note('c:${live.conversation.id}', text);
  }
}

/// 这次跑完的那句话：最后一条回答的第一行。
String summaryOf(LiveSession live) {
  final List<LlmMessage> all = live.conversation.messages;
  for (int i = all.length - 1; i >= 0; i -= 1) {
    final LlmMessage m = all[i];
    if (m.role != LlmRole.assistant) continue;
    final String text = m.text.trim();
    if (text.isEmpty) continue;
    for (final String line in text.split('\n')) {
      final String t = line.trim();
      if (t.isEmpty) continue;
      return t.length > 60 ? '${t.substring(0, 60)}…' : t;
    }
  }
  return '跑完了';
}
