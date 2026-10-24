import 'package:flutter/material.dart';

import '../data/hosts.dart';
import '../data/secrets.dart';
import 'components.dart';
import 'theme.dart';

class HostsPage extends StatefulWidget {
  const HostsPage({
    super.key,
    required this.hosts,
    required this.secrets,
    required this.onChanged,
  });

  final HostStore hosts;
  final SecretStore secrets;
  final VoidCallback onChanged;

  @override
  State<HostsPage> createState() => _HostsPageState();
}

class _HostsPageState extends State<HostsPage> {
  @override
  Widget build(BuildContext context) {
    final List<HostEntry> list = widget.hosts.hosts;
    return Column(
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.ink)),
          ),
          child: Row(
            children: <Widget>[
              const Text('主机', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${list.length} 台', style: C.monoSmall),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _edit(),
                child: Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: C.ink)),
                  child: const Icon(Icons.add, size: 15, color: C.ink),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: list.length,
            itemBuilder: (BuildContext context, int i) => _row(list[i], i),
          ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: C.rule))),
          child: const Text(
            '密钥放在本机安全存储里，不进对话，也不写日志。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _row(HostEntry h, int index) {
    return InkWell(
      onTap: () => _edit(h),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: index == 0 ? C.ink : C.rule),
          ),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 22,
              child: Text('${index + 1}'.padLeft(2, '0'), style: C.monoSmall.copyWith(color: C.grey2)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(h.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(h.address, style: C.monoSmall),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(h.trusted ? '指纹已记' : '指纹待确认',
                    style: TextStyle(fontSize: 11, color: h.trusted ? C.grey : C.blue)),
                const SizedBox(height: 2),
                Text(h.auth == 'key' ? '私钥' : '密码', style: C.monoSmall.copyWith(color: C.grey2)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit([HostEntry? entry]) async {
    final TextEditingController name = TextEditingController(text: entry?.name ?? '');
    final TextEditingController host = TextEditingController(text: entry?.host ?? '');
    final TextEditingController port = TextEditingController(text: '${entry?.port ?? 22}');
    final TextEditingController user = TextEditingController(text: entry?.user ?? '');
    final TextEditingController secret = TextEditingController();
    String auth = entry?.auth ?? 'password';

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx, StateSetter setLocal) {
            return AlertDialog(
              title: Text(entry == null ? '加一台主机' : '改主机',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 380,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      RuleField(controller: name, label: '名字', hint: 'web-01'),
                      Row(
                        children: <Widget>[
                          Expanded(flex: 3, child: RuleField(controller: host, label: '地址', hint: '10.0.0.21')),
                          const SizedBox(width: 12),
                          Expanded(
                            child: RuleField(
                              controller: port,
                              label: '端口',
                              keyboard: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      RuleField(controller: user, label: '账号', hint: 'root'),
                      SectionLabel('认证'),
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          _choice('密码', auth == 'password',
                              () => setLocal(() => auth = 'password')),
                          const SizedBox(width: 8),
                          _choice('私钥', auth == 'key', () => setLocal(() => auth = 'key')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      RuleField(
                        controller: secret,
                        label: auth == 'key' ? '私钥 PEM' : '密码',
                        obscure: auth == 'password',
                        minLines: 2,
                        maxLines: 6,
                        hint: entry == null ? '' : '留空表示不改',
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                if (entry != null)
                  TextButton(
                    onPressed: () async {
                      await widget.hosts.remove(entry.id);
                      await widget.secrets.delete(hostSecretKey(entry.id));
                      if (ctx.mounted) Navigator.of(ctx).pop(false);
                    },
                    child: const Text('删除', style: TextStyle(fontSize: 13, color: C.grey)),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消', style: TextStyle(fontSize: 13, color: C.grey)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('保存', style: TextStyle(fontSize: 13, color: C.ink)),
                ),
              ],
            );
          },
        );
      },
    );

    if (ok != true) return;
    if (name.text.trim().isEmpty || host.text.trim().isEmpty) return;
    if (entry == null && secret.text.isEmpty) return;

    final HostEntry next = HostEntry(
      id: entry?.id ?? HostStore.newId(),
      name: name.text.trim(),
      host: host.text.trim(),
      port: int.tryParse(port.text.trim()) ?? 22,
      user: user.text.trim().isEmpty ? 'root' : user.text.trim(),
      auth: auth,
      fingerprint: entry?.fingerprint ?? '',
    );
    await widget.hosts.upsert(next);
    if (secret.text.isNotEmpty) {
      await widget.secrets.write(hostSecretKey(next.id), secret.text);
    }
    if (!mounted) return;
    setState(() {});
    widget.onChanged();
  }

  Widget _choice(String label, bool on, VoidCallback tap) {
    return GestureDetector(
      onTap: tap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: on ? C.ink : null,
          border: Border.all(color: C.ink),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: on ? C.paper : C.ink)),
      ),
    );
  }
}
