import 'package:flutter/material.dart';

import '../data/hosts.dart';
import '../data/secrets.dart';
import '../tools/ssh_tools.dart';
import 'components.dart';
import 'pet.dart';
import 'resources_page.dart';
import 'theme.dart';

class HostsPage extends StatefulWidget {
  const HostsPage({
    super.key,
    required this.hosts,
    required this.secrets,
    required this.pool,
    required this.onChanged,
  });

  final HostStore hosts;
  final SecretStore secrets;
  final SshPool pool;
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
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      PetAvatar(size: 104),
                      SizedBox(height: 14),
                      Text(
                        '还没有主机。加一台，密钥只留在本机。',
                        style: TextStyle(fontSize: 13.5, height: 1.6, color: C.body),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  itemCount: list.length + 1,
                  itemBuilder: (BuildContext context, int i) {
                    if (i == 0) return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _monitorRow(list.length),
                        );
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _row(list[i - 1], i - 1),
                    );
                  },
                ),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
          child: const Text(
            '密钥保存在本机安全存储，不进对话，也不写日志。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.6),
          ),
        ),
      ],
    );
  }

  /// 资源监看的入口。放在列表最上面一行，不去挤标题栏。
  Widget _monitorRow(int count) {
    return InkWell(
      onTap: _monitor,
      borderRadius: BorderRadius.circular(C.radius),
      child: CardBox(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.blueSoft,
                borderRadius: BorderRadius.circular(C.radiusSmall),
              ),
              child: const Icon(Icons.monitor_heart_outlined, size: 18, color: C.blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('资源监看',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('$count 台的 CPU、内存、磁盘、网络',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: C.monoSmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 16, color: C.grey2),
          ],
        ),
      ),
    );
  }

  void _monitor() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ResourcesPage(hosts: widget.hosts, pool: widget.pool),
      ),
    );
  }

  Widget _row(HostEntry h, int index) {
    return InkWell(
      onTap: () => _edit(h),
      borderRadius: BorderRadius.circular(C.radius),
      child: CardBox(
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.paper2,
                borderRadius: BorderRadius.circular(C.radiusSmall),
              ),
              child: Text('${index + 1}'.padLeft(2, '0'),
                  style: C.monoSmall.copyWith(color: C.grey)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(h.name,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(h.address, style: C.monoSmall),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: h.trusted ? C.paper2 : C.blueSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    h.trusted ? '指纹已记' : '指纹待确认',
                    style: C.monoSmall.copyWith(
                      fontSize: 10,
                      color: h.trusted ? C.grey : C.blue,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(h.auth == 'key' ? '私钥' : '密码',
                    style: C.monoSmall.copyWith(color: C.grey2)),
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
    final TextEditingController sudoPass = TextEditingController();
    String auth = entry?.auth ?? 'password';

    final String? action = await showDialog<String>(
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
                      RuleField(
                        controller: sudoPass,
                        label: 'sudo 密码',
                        obscure: true,
                        hint: '需要提权才填。填一次就存着，命令里不会出现密码',
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
                      await widget.secrets.delete(hostSudoKey(entry.id));
                      if (ctx.mounted) Navigator.of(ctx).pop('delete');
                    },
                    child: const Text('删除', style: TextStyle(fontSize: 13, color: C.grey)),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消', style: TextStyle(fontSize: 13, color: C.grey)),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop('save'),
                  child: const Text('保存', style: TextStyle(fontSize: 13, color: C.ink)),
                ),
              ],
            );
          },
        );
      },
    );

    // 删掉之后要把列表重画一遍，不然那一行还挂在屏幕上。
    if (action == 'delete') {
      if (!mounted) return;
      setState(() {});
      widget.onChanged();
      return;
    }
    if (action != 'save') return;
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
    if (sudoPass.text.isNotEmpty) {
      await widget.secrets.write(hostSudoKey(next.id), sudoPass.text);
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
