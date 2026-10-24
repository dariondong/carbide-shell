import 'dart:async';

import 'package:flutter/material.dart';

import '../core/conversation.dart';
import '../core/models.dart';
import '../core/policy.dart';
import '../data/foreground.dart';
import '../data/providers.dart';
import '../data/secrets.dart';
import '../data/settings.dart';
import '../data/update.dart';
import '../version.dart';
import 'components.dart';
import 'theme.dart';

/// 设置：模型、审批、对话、网络、更新、后台、关于，一页看完。
///
/// 改了就存，右上角写着存没存。文字输入停手 600 毫秒才落盘，切换类当场生效。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.secrets,
    required this.policy,
    required this.conversations,
    required this.onConversationChanged,
    required this.onOpenAbout,
  });

  final SettingsStore settings;
  final SecretStore secrets;
  final ApprovalPolicy policy;

  /// Everything the approval memory lives in: one list per conversation.
  final List<Conversation> conversations;
  final Future<void> Function(Conversation conversation) onConversationChanged;
  final VoidCallback onOpenAbout;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _base;
  late final TextEditingController _model;
  late final TextEditingController _key;
  late final TextEditingController _steps;
  late final TextEditingController _prompt;
  late final TextEditingController _domains;

  String _mode = 'autoRead';
  double _temperature = 0.2;
  double _font = 13.5;
  int _context = 24000;
  bool _stream = true;
  bool _autoUpdate = true;

  String _picked = '';
  String _saved = '';
  String _updateNote = '';
  bool _checking = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final AppSettings s = widget.settings.value;
    _base = TextEditingController(text: s.baseUrl);
    _model = TextEditingController(text: s.model);
    _key = TextEditingController();
    _steps = TextEditingController(text: '${s.maxSteps}');
    _prompt = TextEditingController(text: s.extraPrompt);
    _domains = TextEditingController(text: s.allowedDomains.join('\n'));
    _mode = s.approvalMode;
    _temperature = s.temperature;
    _font = s.answerFont;
    _context = s.contextChars;
    _stream = s.stream;
    _autoUpdate = s.autoCheckUpdate;
    widget.secrets.read(modelSecretKey()).then((String key) {
      if (mounted && key.isNotEmpty) setState(() => _key.text = key);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _base.dispose();
    _model.dispose();
    _key.dispose();
    _steps.dispose();
    _prompt.dispose();
    _domains.dispose();
    super.dispose();
  }

  /// 打字的时候先记一笔，停手一会儿再落盘。
  void _touch() {
    if (_saved.isNotEmpty) setState(() => _saved = '');
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _persist);
  }

  Future<void> _persist() async {
    widget.settings.value
      ..baseUrl = _base.text.trim()
      ..model = _model.text.trim()
      ..maxSteps = _intOf(_steps.text, 12, 1, 50)
      ..temperature = _temperature
      ..approvalMode = _mode
      ..stream = _stream
      ..contextChars = _context
      ..extraPrompt = _prompt.text.trim()
      ..answerFont = _font
      ..autoCheckUpdate = _autoUpdate
      ..allowedDomains = _domains.text
          .split(RegExp(r'[\s,]+'))
          .map((String d) => d.trim())
          .where((String d) => d.isNotEmpty)
          .toList();
    await widget.settings.save();
    await widget.secrets.write(modelSecretKey(), _key.text.trim());
    widget.policy.mode = _mode == 'autoAll'
        ? ApprovalMode.autoAll
        : _mode == 'askAll'
            ? ApprovalMode.askAll
            : ApprovalMode.autoRead;
    if (!mounted) return;
    setState(() => _saved = '已保存');
  }

  static int _intOf(String text, int fallback, int low, int high) {
    final int? n = int.tryParse(text.trim());
    if (n == null) return fallback;
    return n < low ? low : (n > high ? high : n);
  }

  /// 一律立刻存：切换类控件不等人。
  void _apply(VoidCallback change) {
    setState(change);
    _debounce?.cancel();
    _persist();
  }

  /// 把所有对话里「这一类都批准」的记录一次清掉。
  Future<void> _forgetApprovals() async {
    int touched = 0;
    for (final Conversation c in widget.conversations) {
      if (c.kindApprovals.isEmpty && !c.autoApproveAll) continue;
      c.kindApprovals.clear();
      c.autoApproveAll = false;
      await widget.onConversationChanged(c);
      touched += 1;
    }
    if (!mounted) return;
    setState(() => _saved = touched == 0 ? '本来就没有批准的记录' : '清掉了 $touched 个对话的批准');
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _updateNote = '正在问 GitHub…';
    });
    final UpdateChecker checker = UpdateChecker();
    try {
      final List<UpdateInfo> list = await checker.fetch(includePrerelease: true);
      widget.settings.value.lastUpdateCheck = DateTime.now().toIso8601String();
      await widget.settings.save();
      UpdateInfo? best;
      for (final UpdateInfo i in list) {
        if (best == null || compareVersions(i.version, best.version) > 0) best = i;
      }
      if (!mounted) return;
      setState(() {
        _updateNote = best == null
            ? 'GitHub 上还没有发布过版本。'
            : best.newerThanCurrent
                ? '有新版本 ${best.version}'
                : '已经是最新的 $kAppVersion';
      });
    } catch (e) {
      if (mounted) setState(() => _updateNote = '没查成：$e');
    } finally {
      checker.close();
      if (mounted) setState(() => _checking = false);
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
            color: C.card,
            border: Border(bottom: BorderSide(color: C.rule)),
          ),
          child: Row(
            children: <Widget>[
              const Text('设置',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(
                _saved,
                style: C.monoSmall.copyWith(
                  color: _saved == '已保存' ? C.blue : C.grey,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SectionLabel('模型'),
              const SizedBox(height: 8),
              CardBox(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: kLlmPresets.map(_presetChip).toList(),
                    ),
                    if (_picked.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 9),
                      Text(_picked,
                          style: const TextStyle(fontSize: 11.5, color: C.grey, height: 1.5)),
                    ],
                    const SizedBox(height: 14),
                    RuleField(
                      controller: _base,
                      label: '模型地址',
                      hint: 'https://api.example.com/v1',
                      onChanged: (_) => _touch(),
                    ),
                    RuleField(
                      controller: _model,
                      label: '模型名',
                      hint: '支持 tools 的模型',
                      onChanged: (_) => _touch(),
                    ),
                    RuleField(
                      controller: _key,
                      label: '接口密钥',
                      obscure: true,
                      onChanged: (_) => _touch(),
                    ),
                    _choices<double>(
                      '温度',
                      const <double>[0.0, 0.2, 0.7],
                      _temperature,
                      (double v) => '${v.toStringAsFixed(1)}',
                      (double v) => _apply(() => _temperature = v),
                      last: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SectionLabel('审批'),
              const SizedBox(height: 8),
              CardBox(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _choices<String>(
                      '写操作怎么放行',
                      const <String>['autoRead', 'autoAll', 'askAll'],
                      _mode,
                      (String v) => switch (v) {
                        'autoAll' => '全部放行',
                        'askAll' => '全部确认',
                        _ => '写操作确认',
                      },
                      (String v) => _apply(() => _mode = v),
                    ),
                    RuleField(
                      controller: _steps,
                      label: '每轮步数上限',
                      keyboard: TextInputType.number,
                      onChanged: (_) => _touch(),
                    ),
                    _action(
                      '忘掉已批准的写法',
                      '「这一类都批准」的记录一次清空',
                      _forgetApprovals,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SectionLabel('对话'),
              const SizedBox(height: 8),
              CardBox(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _choices<int>(
                      '上下文预算',
                      const <int>[8000, 16000, 24000, 48000],
                      _context,
                      (int v) => v % 1000 == 0 ? '${v ~/ 1000}k' : '$v',
                      (int v) => _apply(() => _context = v),
                    ),
                    _toggle(
                      '逐字显示',
                      _stream,
                      '关掉就是整段一次出来',
                      (bool v) => _apply(() => _stream = v),
                    ),
                    _choices<double>(
                      '回答字号',
                      const <double>[13.0, 13.5, 15.0],
                      _font,
                      (double v) => v <= 13.0
                          ? '小'
                          : v <= 13.5
                              ? '标准'
                              : '大',
                      (double v) => _apply(() => _font = v),
                    ),
                    RuleField(
                      controller: _prompt,
                      label: '附加指示',
                      hint: '每轮都拼在系统提示后面，比如：回答短一点',
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (_) => _touch(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SectionLabel('网络'),
              const SizedBox(height: 8),
              CardBox(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
                child: RuleField(
                  controller: _domains,
                  label: 'http_request 允许的域名',
                  hint: '一行一个，留空表示一个都不许',
                  minLines: 3,
                  maxLines: 6,
                  onChanged: (_) => _touch(),
                ),
              ),
              const SizedBox(height: 22),
              SectionLabel('更新'),
              const SizedBox(height: 8),
              CardBox(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _toggle(
                      '启动时检查新版本',
                      _autoUpdate,
                      '一天最多问一次 GitHub',
                      (bool v) => _apply(() => _autoUpdate = v),
                    ),
                    const RuleLine(),
                    _action(
                      '立即检查',
                      _checking ? '正在问…' : (_updateNote.isEmpty ? '含预发布' : _updateNote),
                      _checkNow,
                    ),
                  ],
                ),
              ),
              if (ForegroundTask.supported) ...<Widget>[
                const SizedBox(height: 22),
                SectionLabel('后台'),
                const SizedBox(height: 8),
                CardBox(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                  child: _action('系统省电设置', '允许后台运行', ForegroundTask.openBatterySettings),
                ),
              ],
              const SizedBox(height: 22),
              SectionLabel('关于'),
              const SizedBox(height: 8),
              CardBox(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: _action('版本', kAppVersion, () async => widget.onOpenAbout()),
              ),
              const SizedBox(height: 18),
              const Text(
                '密钥只存在本机安全存储，不进对话，不会写进日志。',
                style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _presetChip(LlmPreset p) {
    return GestureDetector(
      onTap: () {
        _base.text = p.baseUrl;
        if (p.models.isNotEmpty) _model.text = p.models.first;
        setState(() => _picked = p.note.isEmpty
            ? '已填 ${p.name} 的地址，模型名可以改成 ${p.models.join(' / ')}'
            : '${p.name}：${p.note}');
        _touch();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: C.rule2),
        ),
        child: Text(p.name, style: const TextStyle(fontSize: 12, color: C.ink)),
      ),
    );
  }

  /// 一行标签加几个选项，选中的那个是蓝底白字。
  Widget _choices<T>(
    String label,
    List<T> values,
    T current,
    String Function(T value) nameOf,
    void Function(T value) onPick, {
    bool last = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 11.5, color: C.grey)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values.map((T v) {
              final bool on = v == current;
              return GestureDetector(
                onTap: () => onPick(v),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? C.blue : C.card,
                    borderRadius: BorderRadius.circular(C.radiusSmall),
                    border: Border.all(color: on ? C.blue : C.rule2),
                  ),
                  child: Text(
                    nameOf(v),
                    style: TextStyle(fontSize: 12, color: on ? Colors.white : C.ink),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool value, String note, void Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(fontSize: 13, color: C.ink)),
                const SizedBox(height: 3),
                Text(note, style: const TextStyle(fontSize: 11, color: C.grey, height: 1.4)),
              ],
            ),
          ),
          ToggleKnob(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _action(String label, String note, Future<void> Function() onTap) {
    return InkWell(
      onTap: () => onTap(),
      borderRadius: BorderRadius.circular(C.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: <Widget>[
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13, color: C.ink))),
            if (note.isNotEmpty) ...<Widget>[
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  note,
                  maxLines: 2,
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: C.monoSmall,
                ),
              ),
            ],
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: C.grey2),
          ],
        ),
      ),
    );
  }
}
