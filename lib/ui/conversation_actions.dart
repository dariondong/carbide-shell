import 'package:flutter/material.dart';

import '../core/conversation.dart';
import '../data/hosts.dart';
import '../services.dart';
import 'components.dart';
import 'theme.dart';

/// 新对话的那一问：名字、范围、要不要 Advance Master。
///
/// 列表页和侧边栏都从这里开，免得两处问得不一样。取消返回 null。
Future<Conversation?> newConversationDialog(
  BuildContext context,
  AppServices services,
) async {
  final TextEditingController title = TextEditingController();
  final List<HostEntry> hosts = services.hosts.hosts;
  String hostId = '';
  bool master = false;
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
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('Advance Master', style: TextStyle(fontSize: 13, color: C.ink)),
                        const SizedBox(height: 3),
                        Text(
                          '管全部主机，还能把新主机写进列表。',
                          style: TextStyle(
                            fontSize: 11,
                            color: master ? C.blue : C.grey,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ToggleKnob(
                    value: master,
                    onChanged: (bool v) => setLocal(() {
                      master = v;
                      if (v) hostId = '';
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (master)
                Text(
                  '开了就是全部主机，范围不用选。加主机前它会先问地址和账号。',
                  style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6),
                )
              else ...<Widget>[
                Text('范围', style: TextStyle(fontSize: 11.5, color: C.grey)),
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
                  hostId.isEmpty ? '这个对话可以操作全部主机。' : '这个对话只操作这一台，记忆也保存在它名下。',
                  style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(fontSize: 13, color: C.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('开始', style: TextStyle(fontSize: 13, color: C.blue)),
          ),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  final Conversation c = await services.conversations.create(
    title: title.text.trim().isEmpty ? '新对话' : title.text,
    hostId: hostId,
    advanceMaster: master,
  );
  title.dispose();
  return c;
}

/// 删之前问一句：记录一起删，记忆不动。确认了返回 true。
Future<bool> confirmDeleteConversation(BuildContext context, Conversation c) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('删掉这个对话？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('「${c.title}」的记录会一起删掉，记忆不受影响。',
          style: const TextStyle(fontSize: 13, height: 1.6)),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('取消', style: TextStyle(fontSize: 13, color: C.grey)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text('删除', style: TextStyle(fontSize: 13, color: C.danger)),
        ),
      ],
    ),
  );
  return ok == true;
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
          style: TextStyle(fontSize: 12, color: on ? C.onAccent : C.ink)),
    ),
  );
}
