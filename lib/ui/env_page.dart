import 'package:flutter/material.dart';

import '../data/env_keys.dart';
import 'components.dart';
import 'motion.dart';
import 'theme.dart';

/// 环境密钥：名字、说明在本地文件里，值在安全存储里。
///
/// 这一页上永远看不到值，只有末尾两位。AI 代写的那些也走同一条路：它提，你批准。
class EnvPage extends StatefulWidget {
  const EnvPage({super.key, required this.env});

  final EnvBook env;

  @override
  State<EnvPage> createState() => _EnvPageState();
}

class _EnvPageState extends State<EnvPage> {
  Map<String, String> _masked = <String, String>{};

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final Map<String, String> masked = await widget.env.masked();
    if (!mounted) return;
    setState(() => _masked = masked);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// 加一把或者改一把。名字改不了：要换名字就删了再加。
  Future<void> _edit({EnvKey? existing}) async {
    final TextEditingController name =
        TextEditingController(text: existing?.name ?? '');
    final TextEditingController value = TextEditingController();
    final TextEditingController note =
        TextEditingController(text: existing?.note ?? '');
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(existing == null ? '加一把环境密钥' : '更新 ${existing.name}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('值只写进本机安全存储，页面上只显示末尾两位，日志里一个字的明文都不留。',
                  style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6)),
              const SizedBox(height: 12),
              if (existing == null) ...<Widget>[
                RuleField(
                  controller: name,
                  label: '名字',
                  hint: 'GITHUB_TOKEN',
                ),
              ],
              RuleField(
                controller: value,
                label: existing == null ? '值' : '新的值',
                hint: existing == null ? '粘贴进来就行' : '留空就是不改',
                obscure: true,
              ),
              RuleField(
                controller: note,
                label: '说明',
                hint: '它是干什么用的',
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
            child: const Text('保存', style: TextStyle(fontSize: 13, color: C.blue)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final String key = existing?.name ?? name.text.trim().toUpperCase();
    final String secret = value.text;
    final String desc = note.text.trim();
    name.dispose();
    value.dispose();
    note.dispose();
    if (!validEnvName(key)) {
      _toast('名字要全用大写字母、数字和下划线，并且不以数字开头。');
      return;
    }
    if (secret.isEmpty && existing == null) {
      _toast('值是空的，没存。');
      return;
    }
    if (secret.isNotEmpty) {
      await widget.env.set(key, secret, note: desc);
    } else if (desc.isNotEmpty) {
      // 只改说明：值照旧，重新写一遍再存。
      final String old = await widget.env.value(key);
      await widget.env.set(key, old, note: desc);
    }
    await _refresh();
    _toast('存好了：$key');
  }

  Future<void> _delete(EnvKey key) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('删掉这把密钥？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('${key.name} 和它的值一起删掉，日志里会留一行。',
            style: const TextStyle(fontSize: 13, height: 1.6)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('再想想', style: TextStyle(fontSize: 13, color: C.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(fontSize: 13, color: C.blue)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.env.remove(key.name);
    await _refresh();
    _toast('删掉了 ${key.name}');
  }

  @override
  Widget build(BuildContext context) {
    final List<EnvKey> keys = widget.env.all;
    final List<EnvOp> log = widget.env.log.take(10).toList();
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: const BoxDecoration(
                color: C.card,
                border: Border(bottom: BorderSide(color: C.rule)),
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back, size: 19, color: C.ink),
                  ),
                  const Text('环境密钥',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _edit(),
                    style: TextButton.styleFrom(
                      foregroundColor: C.blue,
                      minimumSize: const Size(0, 34),
                      textStyle: const TextStyle(fontSize: 13),
                    ),
                    child: const Text('加一把'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                children: <Widget>[
                  FadeSlideIn(
                    child: CardBox(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (keys.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('还没有存过。右上角「加一把」写第一把。',
                                  style: TextStyle(fontSize: 12.5, color: C.grey, height: 1.6)),
                            )
                          else
                            for (int i = 0; i < keys.length; i += 1) ...<Widget>[
                              if (i > 0) const RuleLine(),
                              _row(keys[i]),
                            ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (log.isNotEmpty) ...<Widget>[
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: CardBox(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            const Text('操作日志',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 8),
                            for (final EnvOp op in log)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 5),
                                child: Text(
                                  '${_when(op.at)} · ${op.name} · ${op.actionLabel} · ${op.byLabel}',
                                  style: C.monoSmall.copyWith(height: 1.5),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    '值只在本机安全存储里，界面只显示末尾两位。AI 要写一把也得你先点批准，日志只记谁动了哪一把。',
                    style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(EnvKey key) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(key.name, style: C.mono.copyWith(fontSize: 13, color: C.ink)),
                const SizedBox(height: 3),
                Text(
                  <String>[
                    _masked[key.name] ?? '未设',
                    if (key.note.isNotEmpty) key.note,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: C.grey, height: 1.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _edit(existing: key),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text('更新', style: TextStyle(fontSize: 11.5, color: C.blue)),
            ),
          ),
          GestureDetector(
            onTap: () => _delete(key),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text('删除', style: TextStyle(fontSize: 11.5, color: C.grey)),
            ),
          ),
        ],
      ),
    );
  }

  /// 日志上的时间：只写月日时分，年份没意义。
  static String _when(String iso) {
    final DateTime? at = DateTime.tryParse(iso);
    if (at == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
  }
}
