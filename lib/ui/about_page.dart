import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/update.dart';
import '../version.dart';
import 'components.dart';
import 'theme.dart';

/// 关于：版本、项目地址、更新日志、检查更新。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

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
      _status = '正在问 GitHub…';
      _found = null;
    });
    final UpdateChecker checker = UpdateChecker();
    try {
      final List<UpdateInfo> list = await checker.fetch(includePrerelease: _withPre);
      if (!mounted) return;
      if (list.isEmpty) {
        setState(() {
          _status = '没有找到正式版本。';
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
        _status = best.newerThanCurrent
            ? '有新版本 ${best.version}，当前是 $kAppVersion。'
            : '已经是最新的，当前 $kAppVersion。';
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: C.ink)),
          ),
          child: Row(
            children: <Widget>[
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: const Icon(Icons.arrow_back, size: 18, color: C.ink),
              ),
              const SizedBox(width: 12),
              const Text('关于', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Carbide Shell',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4)),
              const SizedBox(height: 4),
              const Text('碳壳 · 一个能连服务器干活的 agent',
                  style: TextStyle(fontSize: 13, color: C.grey)),
              const SizedBox(height: 22),
              const RuleLine(),
              const SizedBox(height: 18),
              KeyValueRow('版本', kAppVersion),
              const SizedBox(height: 6),
              _linkRow('项目地址', kProjectUrl),
              _linkRow('更新日志', kChangelogUrl),
              const SizedBox(height: 24),
              const RuleLine(),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  GestureDetector(
                    onTap: () => setState(() => _withPre = !_withPre),
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _withPre ? C.blue : C.card,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _withPre ? C.blue : C.rule2),
                      ),
                      child: _withPre
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : null,
                    ),
                  ),
                  const Text('含预发布', style: TextStyle(fontSize: 12, color: C.grey)),
                  const SizedBox(width: 14),
                  SquareButton(
                    label: _busy ? '检查中…' : '检查更新',
                    filled: true,
                    onPressed: _busy ? null : _check,
                  ),
                  const SizedBox(width: 12),
                  if (_checked && _found == null)
                    const Text('已是最新', style: TextStyle(fontSize: 12, color: C.grey)),
                ],
              ),
              if (_status.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                Text(_status, style: const TextStyle(fontSize: 12.5, color: C.body, height: 1.6)),
              ],
              if (_found != null) ...<Widget>[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  color: C.paper2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${_found!.tag} · ${_found!.publishedAt.split('T').first}',
                          style: C.monoSmall.copyWith(color: C.ink)),
                      const SizedBox(height: 8),
                      Text(
                        shortNotes(_found!.notes),
                        style: const TextStyle(fontSize: 12.5, height: 1.65, color: C.body),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: <Widget>[
                          SquareButton(
                            label: '下载',
                            filled: true,
                            onPressed: () => _open(_found!.apkUrl.isEmpty ? _found!.pageUrl : _found!.apkUrl),
                          ),
                          const SizedBox(width: 8),
                          SquareButton(label: '打开发布页', onPressed: () => _open(_found!.pageUrl)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 30),
              const RuleLine(),
              const SizedBox(height: 16),
              const Text(
                '密钥与记忆都保存在本机。本页只请求一次 GitHub 的版本列表。',
                style: TextStyle(fontSize: 11, color: C.grey, height: 1.8),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _linkRow(String label, String url) {
    return InkWell(
      onTap: () => _open(url),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.rule))),
        child: Row(
          children: <Widget>[
            Text(label, style: const TextStyle(fontSize: 13, color: C.ink)),
            const Spacer(),
            Flexible(
              child: Text(url,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: C.monoSmall),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.north_east, size: 13, color: C.grey),
          ],
        ),
      ),
    );
  }

}
