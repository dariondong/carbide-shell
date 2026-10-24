import 'package:flutter/material.dart';

import '../core/memory.dart';
import 'components.dart';
import 'theme.dart';

/// Where the long-term memory lives: read it, add to it, delete from it.
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key, required this.memory, required this.onChanged});

  final MemoryStore memory;
  final VoidCallback onChanged;

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  @override
  Widget build(BuildContext context) {
    final List<MemoryEntry> list = widget.memory.entries;
    return Column(
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
          ),
          child: Row(
            children: <Widget>[
              const Text('记忆', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Text('${list.length} 条', style: C.monoSmall),
              const Spacer(),
              GestureDetector(
                onTap: () => _edit(),
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
              ? const Padding(
                  padding: EdgeInsets.fromLTRB(20, 26, 20, 0),
                  child: Text(
                    '还没有记下任何东西。跟它说话的时候说「记住…」，它就会写在这里。',
                    style: TextStyle(fontSize: 13.5, height: 1.6, color: C.body),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  itemCount: list.length,
                  itemBuilder: (BuildContext context, int i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _row(list[i], i),
                  ),
                ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: const Text(
            '每轮对话会把这里最新的内容带进系统提示，最多 1200 字。删掉就不再带。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _row(MemoryEntry e, int index) {
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
                      Text(e.tag, style: C.label.copyWith(color: C.blue)),
                      const SizedBox(width: 8),
                    ],
                    Text(_date(e.at), style: C.monoSmall.copyWith(color: C.grey2)),
                  ],
                ),
                const SizedBox(height: 5),
                Text(e.text, style: C.answer),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              await widget.memory.remove(e.id);
              if (!mounted) return;
              setState(() {});
              widget.onChanged();
            },
            child: const Padding(
              padding: EdgeInsets.only(left: 12, top: 2),
              child: Icon(Icons.close, size: 15, color: C.grey),
            ),
          ),
        ],
      ),
    );
  }

  static String _date(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }

  Future<void> _edit() async {
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
            child: const Text('保存', style: TextStyle(fontSize: 13, color: C.ink)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (text.text.trim().isEmpty) return;
    await widget.memory.add(text.text, tag: tag.text);
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }
}
