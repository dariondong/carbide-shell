import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/usage.dart';
import '../data/update.dart';
import '../data/usage.dart';
import '../version.dart';
import 'components.dart';
import 'motion.dart';
import 'pet.dart';
import 'theme.dart';

/// 关于：版本、这台机器上的东西有多少、更新、项目地址。
class AboutPage extends StatefulWidget {
  const AboutPage({
    super.key,
    this.hostCount = 0,
    this.conversationCount = 0,
    this.usage,
  });

  final int hostCount;
  final int conversationCount;

  /// 今日 token 从这里算，没有就显示「—」。
  final UsageStore? usage;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _busy = false;
  String _status = '';
  UpdateInfo? _found;
  bool _checked = false;
  bool _withPre = true;

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = '正在请求 GitHub';
      _found = null;
    });
    final UpdateChecker checker = UpdateChecker();
    try {
      final List<UpdateInfo> list = await checker.fetch(includePrerelease: _withPre);
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _status = '没有可用的版本';
          _checked = true;
        });
        return;
      }
      UpdateInfo best = list.first;
      for (final UpdateInfo i in list) {
        if (compareVersions(i.version, best.version) > 0) best = i;
      }
      setState(() {
        _checked = true;
        _found = best.newerThanCurrent ? best : null;
        _status = best.newerThanCurrent ? '有新版本 ${best.version}' : '已是最新版本';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = '检查失败：$e');
    } finally {
      checker.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;
    final bool ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('打不开浏览器，链接已复制')),
      );
    }
  }

  String get _tokensToday {
    final UsageStore? store = widget.usage;
    if (store == null) return '—';
    final List<UsageDayRow> days = usageLastDays(store.all, 1);
    if (days.isEmpty) return '—';
    return usageText(days.last.totals.total);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
          ),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(Icons.arrow_back, size: 19, color: C.ink),
                ),
              ),
              const SizedBox(width: 6),
              const Text('关于',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
            children: <Widget>[
              FadeSlideIn(child: _identity()),
              const SizedBox(height: 14),
              FadeSlideIn(delay: const Duration(milliseconds: 60), child: _counts()),
              const SizedBox(height: 14),
              FadeSlideIn(delay: const Duration(milliseconds: 110), child: _updateCard()),
              const SizedBox(height: 14),
              FadeSlideIn(delay: const Duration(milliseconds: 160), child: _projectCard()),
              const SizedBox(height: 14),
              FadeSlideIn(delay: const Duration(milliseconds: 210), child: _storageCard()),
              const SizedBox(height: 22),
              FadeSlideIn(
                delay: const Duration(milliseconds: 250),
                child: Text(
                  'Carbide Shell $kAppVersion',
                  style: C.monoSmall.copyWith(letterSpacing: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _identity() {
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: <Widget>[
          PetAvatar(size: 66, mood: petMoodNow(running: false, waiting: false)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Carbide Shell',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3),
                ),
                const SizedBox(height: 3),
                Text('碳壳 · 通过 SSH 操作服务器的 agent',
                    style: TextStyle(fontSize: 12.5, color: C.grey, height: 1.4)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: C.paper2,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('v$kAppVersion',
                      style: C.monoSmall.copyWith(color: C.ink)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 这台机器上有多少东西：主机、对话、今天花掉的 token。
  Widget _counts() {
    return CardBox(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _countCell('主机', '${widget.hostCount}'),
          ),
          _verticalRule(),
          Expanded(
            child: _countCell('对话', '${widget.conversationCount}'),
          ),
          _verticalRule(),
          Expanded(
            child: _countCell('今日 token', _tokensToday),
          ),
        ],
      ),
    );
  }

  Widget _countCell(String label, String value) {
    return Column(
      children: <Widget>[
        RollingNumber(
          text: value,
          style: const TextStyle(
              fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.3),
          alignment: Alignment.center,
        ),
        const SizedBox(height: 3),
        Text(label, style: C.monoSmall),
      ],
    );
  }

  Widget _verticalRule() {
    return Container(width: 1, height: 30, color: C.rule);
  }

  Widget _updateCard() {
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('更新',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('当前 $kAppVersion', style: C.monoSmall),
              const Spacer(),
              _smallSwitch('含预发布', _withPre, (bool v) => setState(() => _withPre = v)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              SquareButton(
                label: _busy ? '检查中…' : '检查更新',
                filled: true,
                onPressed: _busy ? null : _check,
              ),
              const SizedBox(width: 12),
              if (_status.isNotEmpty)
                Expanded(
                  child: Text(
                    _status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: C.monoSmall.copyWith(
                        color: _checked && _found == null ? C.grey : C.ink),
                  ),
                ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: _found == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const RuleLine(),
                        const SizedBox(height: 12),
                        Text(
                          '${_found!.tag} · ${_found!.publishedAt.split('T').first}',
                          style: C.mono.copyWith(color: C.ink),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          shortNotes(_found!.notes),
                          style: TextStyle(
                              fontSize: 12.5, height: 1.65, color: C.body),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: <Widget>[
                            SquareButton(
                              label: '下载',
                              filled: true,
                              onPressed: () => _open(_found!.apkUrl.isEmpty
                                  ? _found!.pageUrl
                                  : _found!.apkUrl),
                            ),
                            const SizedBox(width: 8),
                            SquareButton(
                              label: '发布页',
                              onPressed: () => _open(_found!.pageUrl),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _smallSwitch(String label, bool value, void Function(bool) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label, style: C.monoSmall),
        const SizedBox(width: 6),
        ToggleKnob(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _projectCard() {
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        children: <Widget>[
          _linkRow('项目地址', kProjectUrl),
          const RuleLine(),
          _linkRow('更新日志', kChangelogUrl),
          const RuleLine(),
          _linkRow('反馈问题', '$kProjectUrl/issues'),
        ],
      ),
    );
  }

  Widget _linkRow(String label, String url) {
    return PressScale(
      onTap: () => _open(url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: <Widget>[
            Text(label, style: TextStyle(fontSize: 13.5, color: C.ink)),
            const Spacer(),
            Flexible(
              child: Text(url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: C.monoSmall),
            ),
            const SizedBox(width: 6),
            Icon(Icons.north_east, size: 13, color: C.grey2),
          ],
        ),
      ),
    );
  }

  Widget _storageCard() {
    return CardBox(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.lock_outline, size: 15, color: C.grey),
              const SizedBox(width: 6),
              Text('存在本机', style: C.label),
            ],
          ),
          const SizedBox(height: 10),
          const KeyValueRow('密钥', '本机安全存储'),
          const KeyValueRow('对话与记忆', '应用数据目录'),
          const KeyValueRow('设置', '应用数据目录'),
          const SizedBox(height: 2),
          Text(
            '本页只请求一次 GitHub 的版本列表，别的都不往外发。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ],
      ),
    );
  }
}
