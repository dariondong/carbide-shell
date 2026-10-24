import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/agent.dart';
import '../core/conversation.dart';
import '../core/llm_base.dart';
import '../core/models.dart';
import '../services.dart';
import 'activity.dart';

/// 一个对话在跑的时候的全部状态。
///
/// 跑的内容不在页面里，所以关掉这一页、切到别的对话去，它照样往下跑；
/// 回到这个对话时看到的是同一个循环、同一段正在长出来的回答。
class LiveSession {
  LiveSession({required this.conversation, required this.session}) {
    session.loop.approver = _LiveApprover(this);
    session.loop.onChanged = () => hub?.touch(this);
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

  DateTime lastNote = DateTime.fromMillisecondsSinceEpoch(0);
  String lastNoteText = '';

  bool get waiting => pending != null;

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
    changed();
    board.note('c:${live.conversation.id}', '${live.conversation.title} · 开跑');
    try {
      return await loop.send(text, cancel: live.cancel, images: images);
    } finally {
      live.running = false;
      live.cancel = null;
      live.pending = null;
      live.conversation.tokensUsed = loop.tokens;
      await services.persist(live.conversation);
      board.done('c:${live.conversation.id}',
          summary: '${live.conversation.title} · ${summaryOf(live)}');
      changed();
    }
  }

  /// 停一轮：正在等确认的也一起放掉。
  void stop(LiveSession live) {
    live.cancel?.cancel();
    live.decide(false);
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
