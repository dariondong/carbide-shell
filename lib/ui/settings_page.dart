import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/models.dart';
import '../core/policy.dart';
import '../data/secrets.dart';
import '../data/settings.dart';
import 'components.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.secrets,
    required this.policy,
    required this.agent,
  });

  final SettingsStore settings;
  final SecretStore secrets;
  final ApprovalPolicy policy;
  final AgentLoop agent;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _base;
  late final TextEditingController _model;
  late final TextEditingController _key;
  late final TextEditingController _steps;
  late final TextEditingController _domains;
  String _mode = 'autoRead';
  String _saved = '';

  @override
  void initState() {
    super.initState();
    final AppSettings s = widget.settings.value;
    _base = TextEditingController(text: s.baseUrl);
    _model = TextEditingController(text: s.model);
    _key = TextEditingController();
    _steps = TextEditingController(text: '${s.maxSteps}');
    _domains = TextEditingController(text: s.allowedDomains.join('\n'));
    _mode = s.approvalMode;
    widget.secrets.read(modelSecretKey()).then((String key) {
      if (mounted && key.isNotEmpty) {
        setState(() => _key.text = key);
      }
    });
  }

  @override
  void dispose() {
    _base.dispose();
    _model.dispose();
    _key.dispose();
    _steps.dispose();
    _domains.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final AppSettings s = widget.settings.value
      ..baseUrl = _base.text.trim()
      ..model = _model.text.trim()
      ..maxSteps = int.tryParse(_steps.text.trim()) ?? 12
      ..approvalMode = _mode
      ..allowedDomains = _domains.text
          .split(RegExp(r'[\s,]+'))
          .map((String d) => d.trim())
          .where((String d) => d.isNotEmpty)
          .toList();
    await widget.settings.save();
    await widget.secrets.write(modelSecretKey(), _key.text.trim());
    widget.policy.mode = s.approvalMode == 'autoAll'
        ? ApprovalMode.autoAll
        : s.approvalMode == 'askAll'
            ? ApprovalMode.askAll
            : ApprovalMode.autoRead;
    widget.agent.maxSteps = s.maxSteps;
    if (!mounted) return;
    setState(() => _saved = '已保存');
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
          alignment: Alignment.centerLeft,
          child: const Text('设置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              RuleField(controller: _base, label: '模型地址', hint: 'https://api.example.com/v1'),
              RuleField(controller: _model, label: '模型名', hint: '随便一个支持 tools 的模型'),
              RuleField(controller: _key, label: '接口密钥', obscure: true),
              SectionLabel('审批'),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  _modeChip('autoRead', '写操作确认'),
                  const SizedBox(width: 8),
                  _modeChip('autoAll', '全部放行'),
                  const SizedBox(width: 8),
                  _modeChip('askAll', '全部确认'),
                ],
              ),
              const SizedBox(height: 18),
              RuleField(
                controller: _steps,
                label: '每轮步数上限',
                keyboard: TextInputType.number,
              ),
              RuleField(
                controller: _domains,
                label: 'http_request 允许的域名',
                hint: '一行一个，留空表示都不许',
                minLines: 3,
                maxLines: 6,
              ),
              Row(
                children: <Widget>[
                  SquareButton(label: '保存', filled: true, onPressed: _save),
                  const SizedBox(width: 12),
                  Text(_saved, style: const TextStyle(fontSize: 12, color: C.grey)),
                ],
              ),
              const SizedBox(height: 30),
              const RuleLine(),
              const SizedBox(height: 14),
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

  Widget _modeChip(String value, String label) {
    final bool on = _mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mode = value),
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? C.ink : null,
            border: Border.all(color: C.ink),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, color: on ? C.paper : C.ink)),
        ),
      ),
    );
  }
}
