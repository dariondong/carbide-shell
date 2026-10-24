import 'package:flutter/material.dart';

import '../core/memory.dart';
import '../data/hosts.dart';
import '../services.dart';
import 'components.dart';
import 'theme.dart';

/// Long-term memory, one file per scope: 全局 plus every host.
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.services, required this.onChanged});

  final AppServices services;
  final VoidCallback onChanged;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  String _scope = MemoryBook.globalScope;
  MemoryStore? _store;

  @override
  void initState() {
    super.initState();
    _load(_scope);
  }

  Future<void> _load(String scope) async {
    final MemoryStore store = await widget.services.memory.open(scope);
    if (!mounted) return;
    setState(() {
      _scope = scope;
      _store = store;
    });
  }

  String get _scopeLabel {
    if (_scope == MemoryBook.globalScope) return '全局';
    final HostEntry? host = widget.services.hosts.byId(_scope);
    return host?.name ?? '未知主机';
  }

  @override
  Widget build(BuildContext context) {
    final MemoryStore? store = _store;
    final List<MemoryEntry> list = store?.entries ?? <MemoryEntry>[];
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
              const Text('记忆',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.2)),
              const SizedBox(width: 8),
              Text('${list.length} 条', style: C.monoSmall),
              const Spacer(),
              GestureDetector(
                onTap: store == null ? null : () => _edit(store),
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
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: <Widget>[
              _scopeChip(MemoryBook.globalScope, '全局'),
              for (final HostEntry h in widget.services.hosts.hosts)
                _scopeChip(h.id, h.name),
            ],
          ),
        ),
        Expanded(
          child: store == null
              ? const SizedBox.shrink()
              : list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Text(
                        _scope == MemoryBook.globalScope
                            ? '还没有全局记忆。说「记住…」它就会写在这里。'
                            : '这台机器还没有记忆。绑定它的对话里说「记住…」就会写到这里。',
                        style: const TextStyle(fontSize: 13.5, height: 1.6, color: C.body),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                      itemCount: list.length,
                      itemBuilder: (BuildContext context, int i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _row(store, list[i]),
                      ),
                    ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Text(
            '当前「$_scopeLabel」。绑定单台主机的对话只带它自己的记忆，多机对话带全局记忆。每轮最多 1200 字。',
            style: const TextStyle(fontSize: 11, color: C.grey, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _scopeChip(String scope, String label) {
    final bool on = _scope == scope;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _load(scope),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? C.blue : C.card,
            borderRadius: BorderRadius.circular(C.radiusSmall),
            border: Border.all(color: on ? C.blue : C.rule2),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, color: on ? Colors.white : C.ink)),
        ),
      ),
    );
  }

  Widget _row(MemoryStore store, MemoryEntry e) {
    return CardBox(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (e.tag.isNotEmpty) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: C.blueSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(e.tag,
                            style: C.monoSmall.copyWith(color: C.blue, fontSize: 9.5)),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(_date(e.at), style: C.monoSmall.copyWith(color: C.grey2)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(e.text, style: C.answer),
              ],
            ),
          ),
          IconButton(
            onPressed: () async {
              await store.remove(e.id);
              if (!mounted) return;
              setState(() {});
              widget.onChanged();
            },
            icon: const Icon(Icons.close, size: 15, color: C.grey2),
            splashRadius: 16,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  static String _date(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }

  Future<void> _edit(MemoryStore store) async {
    final TextEditingController text = TextEditingController();
    final TextEditingController tag = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('记一件事', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              RuleField(controller: text, label: '内容', minLines: 3, maxLines: 8),
              RuleField(controller: tag, label: '分类（可不填）', hint: '偏好 / 主机 / 规则'),
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
            child: const Text('保存', style: TextStyle(fontSize: 13, color: C.blue)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (text.text.trim().isEmpty) return;
    await store.add(text.text, tag: tag.text);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }
}
