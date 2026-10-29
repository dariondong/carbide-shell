import 'package:flutter/material.dart';

import '../core/conversation.dart';
import '../data/hosts.dart';
import '../data/hub.dart';
import '../services.dart';
import 'components.dart';
import 'conversation_actions.dart';
import 'motion.dart';
import 'pet.dart';
import 'theme.dart';

/// The list of conversations. Each one is a scope plus a transcript.
class ConversationsPage extends StatefulWidget {
  const ConversationsPage({
    super.key,
    required this.services,
    required this.hub,
    required this.onOpen,
    required this.onChanged,
  });

  final AppServices services;
  final SessionHub hub;
  final void Function(Conversation) onOpen;
  final VoidCallback onChanged;

  @override
  State<ConversationsPage> createState() => _ConversationsPageState();
}

class _ConversationsPageState extends State<ConversationsPage> {
  @override
  Widget build(BuildContext context) {
    final List<Conversation> list = widget.services.conversations.all;
    return Column(
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
          ),
          child: Row(
            children: <Widget>[
              const Text('会话',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              const SizedBox(width: 8),
              Text('${list.length}', style: C.monoSmall),
              const Spacer(),
              GestureDetector(
                onTap: () => _new(),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: C.blue,
                    borderRadius: BorderRadius.circular(C.radiusSmall),
                  ),
                  child: Icon(Icons.add, size: 17, color: C.onAccent),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _empty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  itemCount: list.length,
                  itemBuilder: (BuildContext context, int i) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: FadeSlideIn(
                      delay: Duration(milliseconds: 40 * (i < 6 ? i : 6)),
                      child: _row(list[i]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 34, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const PetAvatar(size: 112),
          const SizedBox(height: 14),
          const Text('还没有对话',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          Text(
            '一个对话可以管全部主机，也可以只管某一台。只管一台的时候，记忆也存在那台机器名下。',
            style: C.answer,
          ),
          const SizedBox(height: 20),
          SquareButton(label: '开一个', filled: true, onPressed: () => _new()),
        ],
      ),
    );
  }

  Widget _row(Conversation c) {
    final HostEntry? host = c.multiHost ? null : widget.services.hosts.byId(c.hostId);
    final String scope = c.multiHost
        ? (c.advanceMaster ? '全部主机 · Advance Master' : '全部主机')
        : (host == null ? '主机已删除' : '${host.name} · ${host.address}');
    final String meta = '${c.turns} 轮 · ${_tokens(c.tokensUsed)} tok · ${_ago(c.updatedAt)}';
    final bool waiting = widget.hub.isWaiting(c.id);
    final bool busy = widget.hub.isRunning(c.id);
    return PressScale(
      onTap: () => widget.onOpen(c),
      behavior: HitTestBehavior.deferToChild,
      child: CardBox(
        padding: const EdgeInsets.fromLTRB(16, 15, 10, 15),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                      ),
                      if (waiting) ...<Widget>[
                        const SizedBox(width: 7),
                        _tag('等你确认', C.blue, C.blueSoft),
                      ] else if (busy) ...<Widget>[
                        const SizedBox(width: 7),
                        _tag('在跑', C.blue, C.blueSoft),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(scope, maxLines: 1, overflow: TextOverflow.ellipsis, style: C.monoSmall),
                  const SizedBox(height: 3),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: C.grey2, height: 1.5)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: () => _delete(c),
              icon: Icon(Icons.close, size: 15, color: C.grey2),
              splashRadius: 16,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _tag(String text, Color fg, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: C.monoSmall.copyWith(fontSize: 9.5, color: fg, height: 1.4)),
    );
  }

  static String _tokens(int n) {
    if (n < 1000) return '$n';
    final double k = n / 1000;
    return '${k.toStringAsFixed(k < 10 ? 1 : 0)}k';
  }

  static String _ago(DateTime at) {
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return '刚刚';
    if (d.inHours < 1) return '${d.inMinutes} 分钟前';
    if (d.inDays < 1) return '${d.inHours} 小时前';
    return '${d.inDays} 天前';
  }

  Future<void> _delete(Conversation c) async {
    final bool ok = await confirmDeleteConversation(context, c);
    if (!ok) return;
    await widget.services.conversations.remove(c.id);
    widget.hub.forget(c.id);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _new() async {
    final Conversation? c = await newConversationDialog(context, widget.services);
    if (c == null || !mounted) return;
    widget.onChanged();
    widget.onOpen(c);
  }
}
