import 'dart:async';

import '../core/conversation.dart';
import '../services.dart';
import 'activity.dart';
import 'hub.dart';

/// 通知里写的那一句，发到该去的地方。
///
/// 人是从通知上回的，所以目标由「刚才在说话的是谁」定：最近那个对话。这时它可能在
/// 等模型提问、可能还在跑、也可能已经停了，三种接法不一样：
/// - 在等提问，这句话就是对提问的回答；
/// - 还在跑，先排在后面，这一轮完了接着发；
/// - 停了，直接当新的一轮发出去。
class NoticeReply {
  NoticeReply({required this.services, required this.hub, required this.board});

  final AppServices services;
  final SessionHub hub;
  final ActivityBoard board;

  /// 送出去，返回它落在哪个对话上；没地方可去就是空串。
  Future<String> deliver(String raw) async {
    final String text = raw.trim();
    if (text.isEmpty) return '';
    final Conversation? target = _target();
    if (target == null) return '';
    final LiveSession live = await hub.open(target);
    if (live.pendingAsk != null) {
      live.answerAsk(text);
      return target.id;
    }
    if (live.running) {
      hub.enqueue(target.id, text);
      return target.id;
    }
    unawaited(hub.send(live, text));
    return target.id;
  }

  /// 最近说过话的那个对话；没有就发给最新的那一个。
  Conversation? _target() {
    final String id = board.lastConversationId;
    if (id.isNotEmpty) {
      final Conversation? hit = services.conversations.byId(id);
      if (hit != null) return hit;
    }
    final List<Conversation> all = services.conversations.all;
    return all.isEmpty ? null : all.first;
  }
}
