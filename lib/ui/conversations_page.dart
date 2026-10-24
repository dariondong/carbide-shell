import 'package:flutter/material.dart';

import '../core/conversation.dart';
import '../data/hosts.dart';
import '../services.dart';
import 'components.dart';
import 'theme.dart';

/// The list of conversations. Each one is a scope plus a transcript.
class ConversationsPage extends StatefulWidget {
  const ConversationsPage({
    super.key,
    required this.services,
    required this.onOpen,
    required this.onChanged,
  });

  final AppServices services;
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
          decoration: const BoxDecoration(
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
                  child: const Icon(Icons.add, size: 17, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? _empty()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  itemCount: list.length,
                  itemBuilder: (BuildContext context, int i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _row(list[i]),
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
          const Text('还没有对话',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          const Text(
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
        ? '全部主机'
        : (host == null ? '主机已删除' : '${host.name} · ${host.address}');
    return InkWell(
      onTap: () => widget.onOpen(c),
      borderRadius: BorderRadius.circular(C.radius),
      child: CardBox(
        padding: const EdgeInsets.fromLTRB(14, 13, 8, 13),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(scope, maxLines: 1, overflow: TextOverflow.ellipsis, style: C.monoSmall),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text('${c.turns} 轮',
                    style: C.monoSmall.copyWith(color: C.grey2)),
                const SizedBox(height: 2),
                Text('${_tokens(c.tokensUsed)} tok',
                    style: C.monoSmall.copyWith(color: C.grey2)),
                const SizedBox(height: 4),
                Text(_ago(c.updatedAt), style: C.monoSmall.copyWith(color: C.grey2)),
              ],
            ),
            IconButton(
              onPressed: () => _delete(c),
              icon: const Icon(Icons.close, size: 15, color: C.grey2),
              splashRadius: 16,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
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
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删掉这个对话？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('「${c.title}」的记录会一起删掉，记忆不受影响。',
            style: const TextStyle(fontSize: 13, height: 1.6)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(fontSize: 13, color: C.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(fontSize: 13, color: Color(0xFFD7443E))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.services.conversations.remove(c.id);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  Future<void> _new() async {
    final TextEditingController title = TextEditingController();
    final List<HostEntry> hosts = widget.services.hosts.hosts;
    String hostId = '';
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setLocal) => AlertDialog(
          title: const Text('新对话', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                RuleField(controller: title, label: '名字', hint: '磁盘清理'),
                const Text('范围', style: TextStyle(fontSize: 11.5, color: C.grey)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    _scopeChip('全部主机', hostId.isEmpty, () => setLocal(() => hostId = '')),
                    for (final HostEntry h in hosts)
                      _scopeChip(h.name, hostId == h.id, () => setLocal(() => hostId = h.id)),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  hostId.isEmpty
                      ? '这个对话可以操作全部主机。'
                      : '这个对话只管这一台，记忆也单独存在它名下。',
                  style: const TextStyle(fontSize: 11.5, color: C.grey, height: 1.6),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消', style: TextStyle(fontSize: 13, color: C.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('开始', style: TextStyle(fontSize: 13, color: C.blue)),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final Conversation c = await widget.services.conversations.create(
      title: title.text.trim().isEmpty ? '新对话' : title.text,
      hostId: hostId,
    );
    if (!mounted) return;
    widget.onChanged();
    widget.onOpen(c);
  }

  Widget _scopeChip(String label, bool on, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? C.blue : C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: on ? C.blue : C.rule2),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: on ? Colors.white : C.ink)),
      ),
    );
  }
}
