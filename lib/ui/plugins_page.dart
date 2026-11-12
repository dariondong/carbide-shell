import 'package:flutter/material.dart';

import '../core/plugin.dart';
import '../data/hosts.dart';
import '../data/plugins.dart';
import 'components.dart';
import 'theme.dart';

/// 插件：装在一台代理机上，手机只留清单。
///
/// 这一页要讲清三件事：为什么得有一台代理机、代理机上现在什么状态、
/// 装了的这些插件各自能干什么。所以最上面先选机器，中间是插件，最后才是装新的。
class PluginsPage extends StatefulWidget {
  const PluginsPage({
    super.key,
    required this.plugins,
    required this.hosts,
  });

  final PluginStore plugins;
  final HostStore hosts;

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  final TextEditingController _pkg = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.plugins.addListener(_tick);
  }

  @override
  void dispose() {
    widget.plugins.removeListener(_tick);
    _pkg.dispose();
    super.dispose();
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  PluginStore get _store => widget.plugins;

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _toast('$e');
    }
  }

  // ------------------------------------------------------------ 代理机

  Future<void> _pickProxy() async {
    final List<HostEntry> all = widget.hosts.hosts;
    if (all.isEmpty) {
      _toast('还没有主机。先去「主机」里加一台。');
      return;
    }
    final HostEntry? picked = await showModalBottomSheet<HostEntry>(
      context: context,
      backgroundColor: C.card,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: Text('拿哪台机器当插件代理', style: C.label),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: all
                    .map((HostEntry h) => ListTile(
                          title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(h.address, style: C.monoSmall),
                          trailing: h.id == _store.proxyHostId
                              ? Icon(Icons.check, size: 18, color: C.blue)
                              : null,
                          onTap: () => Navigator.of(ctx).pop(h),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _guard(() async {
      await _store.rememberProxy(picked.id);
      await _store.deploy();
    });
  }

  Future<void> _editRoot() async {
    final TextEditingController root = TextEditingController(text: _store.proxyRoot);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('装在代理机的哪个目录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('留空就是 ~/.carbide/plugins。node 和桥脚本也放这儿，换目录等于重装一遍。',
                style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6)),
            const SizedBox(height: 12),
            RuleField(controller: root, label: '目录', hint: '~/.carbide/plugins'),
          ],
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('算了')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('就这儿')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _guard(() async {
      await _store.rememberProxy(_store.proxyHostId, root: root.text.trim());
      _store.status = const ProxyStatus();
      await _store.deploy();
    });
  }

  // ------------------------------------------------------------ 插件

  Future<void> _install() async {
    final String pkg = _pkg.text.trim();
    if (pkg.isEmpty) {
      _toast('先写个包名。');
      return;
    }
    await _guard(() async {
      final PluginManifest m = await _store.install(pkg);
      _pkg.clear();
      _toast('${m.label} 装好了，带进来 ${m.tools.length} 个工具。');
    });
  }

  Future<void> _remove(PluginManifest m) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text('删掉 ${m.label}？', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('代理机上的包会一起删掉。', style: TextStyle(fontSize: 12.5, color: C.grey, height: 1.6)),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('算了')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('删')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _guard(() => _store.uninstall(m.id));
  }

  /// 改插件配置。有些插件在装配阶段就校验配置，缺了连工具清单都出不来，
  /// 这时候光有「装上了」没用，得让人把配置填进去。
  Future<void> _editConfig(PluginManifest m) async {
    final TextEditingController cfg = TextEditingController(text: m.config);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('插件配置',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('填 JSON。留空表示这个插件不需要配置。存下会重新取一次工具清单，配置不对当场报错。',
                style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6)),
            const SizedBox(height: 12),
            TextField(
              controller: cfg,
              maxLines: 7,
              minLines: 3,
              style: C.mono,
              decoration: const InputDecoration(
                hintText: '{"allowParallelInProgress": false}',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false), child: const Text('算了')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true), child: const Text('存下')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _guard(() => _store.setConfig(m.id, cfg.text.trim()));
  }

  Future<void> _setRisk(PluginManifest m, PluginToolSpec t) async {
    final String? picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.card,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Text('${t.name} 会改东西吗', style: C.label),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text('插件本身不标这个。判成「会改」的话，每次调它都要先问你一句。',
                  style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6)),
            ),
            ListTile(
              leading: Icon(Icons.visibility_outlined, size: 20, color: C.grey),
              title: const Text('只看不动'),
              subtitle: const Text('读完就给答案，不问'),
              onTap: () => Navigator.of(ctx).pop('read'),
            ),
            ListTile(
              leading: Icon(Icons.edit_outlined, size: 20, color: C.grey),
              title: const Text('会改东西'),
              subtitle: const Text('动之前先问一句'),
              onTap: () => Navigator.of(ctx).pop('write'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _guard(() => _store.setToolRisk(m.id, t.name, picked));
  }

  // ------------------------------------------------------------ 画

  @override
  Widget build(BuildContext context) {
    final List<PluginManifest> list = _store.plugins;
    return Scaffold(
      backgroundColor: C.paper,
      appBar: AppBar(
        backgroundColor: C.paper,
        elevation: 0,
        title: const Text('插件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: <Widget>[
          if (_store.busy.isNotEmpty) ...<Widget>[
            LinearProgressIndicator(minHeight: 2, backgroundColor: C.rule2, color: C.blue),
            const SizedBox(height: 8),
            Text('${_store.busy}…', style: C.monoSmall),
            const SizedBox(height: 12),
          ],
          _proxyCard(),
          const SizedBox(height: 20),
          const SectionLabel('已装插件'),
          const SizedBox(height: 8),
          if (list.isEmpty)
            CardBox(
              child: Text(
                '还没有。插件装在代理机上，不是装在手机里——手机上跑不了 npm，也开不了 Node。',
                style: TextStyle(fontSize: 12, color: C.grey, height: 1.7),
              ),
            )
          else
            ...list.map(_pluginCard),
          const SizedBox(height: 20),
          const SectionLabel('装一个新的'),
          const SizedBox(height: 8),
          _installCard(),
        ],
      ),
    );
  }

  Widget _proxyCard() {
    final HostEntry? host = _store.proxyHost;
    final ProxyStatus st = _store.status;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(host == null ? '还没选机器' : host.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      host == null ? '插件得放在一台能跑 Node 的机器上' : host.address,
                      style: C.monoSmall,
                    ),
                  ],
                ),
              ),
              SquareButton(label: host == null ? '选一台' : '换一台', onPressed: _pickProxy),
            ],
          ),
          const SizedBox(height: 12),
          RuleLine(),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  st.ok ? st.summary : (st.error.isEmpty ? '还没部署' : st.error),
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.5,
                    color: st.ok ? C.grey : (st.error.isEmpty ? C.grey2 : C.danger),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SquareButton(
                label: st.ok ? '体检' : '部署',
                tone: 'ink',
                onPressed: host == null
                    ? null
                    : () => _guard(() async {
                          final ProxyStatus r = await _store.deploy();
                          _toast(r.ok ? '代理机就绪：${r.summary}' : '没成：${r.error}');
                        }),
              ),
            ],
          ),
          if (st.ok) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                TextButton(
                  onPressed: _editRoot,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 26),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('装在 ${st.root}', style: TextStyle(fontSize: 11, color: C.blue)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Text(
            '代理机不需要开端口、不需要常驻服务、不用装 dsh。就多了个 Node 和一个不到 20K 的桥脚本，'
            '跑的仍是这条 SSH 连接。',
            style: TextStyle(fontSize: 11, color: C.grey2, height: 1.7),
          ),
        ],
      ),
    );
  }

  Widget _pluginCard(PluginManifest m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(m.label,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(m.note, style: C.monoSmall),
                    ],
                  ),
                ),
                ToggleKnob(
                  value: m.on,
                  onChanged: (bool v) => _guard(() => _store.setOn(m.id, v)),
                ),
              ],
            ),
            if (m.tools.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              RuleLine(),
              const SizedBox(height: 6),
              ...m.tools.map((PluginToolSpec t) => InkWell(
                    onTap: () => _setRisk(m, t),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(t.name,
                                style: C.mono, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: t.isRead ? C.blueSoft : C.rule2,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              t.isRead ? '只看' : '会改',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: t.isRead ? C.blue : C.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
            ],
            if (m.missingSeams.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                '代理机上没有这几项服务，用到它们的工具会直接报错（不是猜的，是它真的说过要用）：${m.missingSeams.join('、')}',
                style: TextStyle(fontSize: 11, color: C.danger, height: 1.6),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                SquareButton(
                  label: '重取清单',
                  tone: 'ink',
                  onPressed: () => _guard(() async {
                    final PluginManifest fresh = await _store.refresh(m.id);
                    _toast('${fresh.label}：${fresh.tools.length} 个工具');
                  }),
                ),
                const SizedBox(width: 8),
                SquareButton(
                  label: m.config.isEmpty ? '配置' : '配置 ·已填',
                  tone: 'ink',
                  onPressed: () => _editConfig(m),
                ),
                const SizedBox(width: 8),
                SquareButton(
                  label: '删除',
                  tone: 'ink',
                  onPressed: () => _remove(m),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _installCard() {
    final bool ready = _store.status.ok;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          RuleField(
            controller: _pkg,
            label: 'npm 包名',
            hint: '@deepseek-ai/dsh-tool-fs',
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  ready ? '装到代理机的 node_modules 里，装完顺手把工具清单收回来。' : '先把代理机部署好。',
                  style: TextStyle(fontSize: 11, color: C.grey2, height: 1.6),
                ),
              ),
              SquareButton(
                label: '安装',
                filled: true,
                onPressed: (ready && _store.busy.isEmpty) ? _install : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
