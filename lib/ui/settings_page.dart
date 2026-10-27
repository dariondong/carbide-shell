import 'dart:async';

import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/conversation.dart';
import '../core/models.dart';
import '../core/policy.dart';
import '../core/smtp.dart';
import '../core/usage.dart';
import '../data/foreground.dart';
import '../data/mail.dart';
import '../data/providers.dart';
import '../data/secrets.dart';
import '../data/settings.dart';
import '../data/usage.dart';
import '../data/update.dart';
import '../version.dart';
import 'components.dart';
import 'motion.dart';
import 'theme.dart';

/// 设置：一页是模块清单，点进去才是那个模块的东西。
///
/// 改了就存，标题栏右侧写着存没存。文字输入停手 600 毫秒才落盘，切换类当场生效。
/// 所有控制器都留在这一层，子页只是换个地方摆它们。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.secrets,
    required this.policy,
    required this.conversations,
    required this.onConversationChanged,
    required this.onOpenAbout,
    required this.onOpenUsage,
    required this.onOpenFiles,
    required this.filesSummary,
    required this.usage,
    required this.mail,
  });

  final SettingsStore settings;
  final SecretStore secrets;
  final ApprovalPolicy policy;

  /// Everything the approval memory lives in: one list per conversation.
  final List<Conversation> conversations;
  final Future<void> Function(Conversation conversation) onConversationChanged;
  final VoidCallback onOpenAbout;
  final VoidCallback onOpenUsage;

  /// 临时文件区是单独一页，设置里留一个入口。
  final VoidCallback onOpenFiles;

  /// 那一行右边写「N 个 · 总量」，进页面前就知道里面轻重。
  final String filesSummary;

  final UsageStore usage;

  /// 邮件通知的设置。
  final MailStore mail;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _base;
  late final TextEditingController _model;
  late final TextEditingController _key;
  late final TextEditingController _steps;
  late final TextEditingController _prompt;
  late final TextEditingController _sys;
  late final TextEditingController _domains;

  String _mode = 'autoRead';
  double _temperature = 0.2;
  double _font = 13.5;
  int _context = 60000;
  bool _stream = true;
  bool _autoUpdate = true;

  String _picked = '';
  String _saved = '';
  String _updateNote = '';
  bool _checking = false;
  Timer? _debounce;

  /// 现在能不能弹通知，进页时问一次原生。
  NotifyState _notify = const NotifyState();

  /// 通知长什么样：一行、折开、一行一条、像聊天。
  String _notifStyle = 'simple';

  late final TextEditingController _mailHost;
  late final TextEditingController _mailPort;
  late final TextEditingController _mailUser;
  late final TextEditingController _mailPass;
  late final TextEditingController _mailFrom;
  late final TextEditingController _mailTo;
  bool _mailOn = false;
  bool _mailSecure = true;
  bool _mailHtml = true;
  String _mailNote = '';

  /// 子页靠它重画：控制器在这一层，改动也发生在这一层。
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final AppSettings s = widget.settings.value;
    _base = TextEditingController(text: s.baseUrl);
    _model = TextEditingController(text: s.model);
    _key = TextEditingController();
    _steps = TextEditingController(text: '${s.maxSteps}');
    _prompt = TextEditingController(text: s.extraPrompt);
    _sys = TextEditingController(text: s.systemPrompt);
    _domains = TextEditingController(text: s.allowedDomains.join('\n'));
    final SmtpConfig m = widget.mail.value;
    _mailHost = TextEditingController(text: m.host);
    _mailPort = TextEditingController(text: '${m.port}');
    _mailUser = TextEditingController(text: m.user);
    _mailPass = TextEditingController();
    _mailFrom = TextEditingController(text: m.from);
    _mailTo = TextEditingController(text: m.to);
    _mailOn = m.enabled;
    _mailSecure = m.secure;
    _mailHtml = m.html;
    _mode = s.approvalMode;
    _temperature = s.temperature;
    _font = s.answerFont;
    _context = s.contextChars;
    _stream = s.stream;
    _autoUpdate = s.autoCheckUpdate;
    _notifStyle = s.notifStyle;
    widget.secrets.read(modelSecretKey()).then((String key) {
      if (mounted && key.isNotEmpty) setState(() => _key.text = key);
    });
    _readNotify();
    widget.mail.password().then((String p) {
      if (mounted && p.isNotEmpty) setState(() => _mailPass.text = p);
    });
  }

  Future<void> _readNotify() async {
    final NotifyState state = await ForegroundTask.state();
    if (mounted) setState(() => _notify = state);
  }

  /// 要一次通知权限；系统已经不再弹框的话，把人送去通知设置页。
  Future<void> _askNotify() async {
    final NotifyState before = _notify;
    final NotifyState after = await ForegroundTask.request();
    if (!mounted) return;
    setState(() => _notify = after);
    if (!after.granted && before.granted == after.granted) {
      await ForegroundTask.openNotificationSettings();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tick.dispose();
    _base.dispose();
    _model.dispose();
    _key.dispose();
    _steps.dispose();
    _prompt.dispose();
    _sys.dispose();
    _domains.dispose();
    _mailHost.dispose();
    _mailPort.dispose();
    _mailUser.dispose();
    _mailPass.dispose();
    _mailFrom.dispose();
    _mailTo.dispose();
    super.dispose();
  }

  void _bump() => _tick.value = _tick.value + 1;

  /// 标题栏那句「已保存」。子页要跟着变，所以走一次 bump。
  void _setSaved(String text) {
    if (!mounted) return;
    setState(() => _saved = text);
    _bump();
  }

  /// 打字的时候先记一笔，停手一会儿再落盘。
  void _touch() {
    if (_saved.isNotEmpty) _setSaved('');
    _bump();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _persist);
  }

  Future<void> _persist() async {
    widget.settings.value
      ..baseUrl = _base.text.trim()
      ..model = _model.text.trim()
      ..maxSteps = _intOf(_steps.text, 12, 1, 200)
      ..temperature = _temperature
      ..approvalMode = _mode
      ..stream = _stream
      ..contextChars = _context
      ..extraPrompt = _prompt.text.trim()
      ..systemPrompt = _sys.text.trim()
      ..answerFont = _font
      ..autoCheckUpdate = _autoUpdate
      ..notifStyle = _notifStyle
      ..allowedDomains = _domains.text
          .split(RegExp(r'[\s,]+'))
          .map((String d) => d.trim())
          .where((String d) => d.isNotEmpty)
          .toList();
    await widget.settings.save();
    await widget.secrets.write(modelSecretKey(), _key.text.trim());
    widget.mail.value = SmtpConfig(
      enabled: _mailOn,
      host: _mailHost.text.trim(),
      port: _intOf(_mailPort.text, 465, 1, 65535),
      secure: _mailSecure,
      user: _mailUser.text.trim(),
      from: _mailFrom.text.trim(),
      to: _mailTo.text.trim(),
      html: _mailHtml,
    );
    await widget.mail.save();
    await widget.mail.setPassword(_mailPass.text.trim());
    widget.policy.mode = _mode == 'autoAll'
        ? ApprovalMode.autoAll
        : _mode == 'askAll'
            ? ApprovalMode.askAll
            : ApprovalMode.autoRead;
    _setSaved('已保存');
  }

  /// 通知样式的名字。设置里选的、列表上写的都是这一份。
  static String _styleName(String value) => switch (value) {
        'big' => '大文本',
        'list' => '列表',
        'chat' => '会话',
        _ => '简洁',
      };

  static int _intOf(String text, int fallback, int low, int high) {    final int? n = int.tryParse(text.trim());
    if (n == null) return fallback;
    return n < low ? low : (n > high ? high : n);
  }

  /// 一律立刻存：切换类控件不等人。
  void _apply(VoidCallback change) {
    setState(change);
    _bump();
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
    _setSaved(touched == 0 ? '本来就没有批准的记录' : '清掉了 $touched 个对话的批准');
  }

  /// 内置那份长什么样，让用户看得见再决定要不要换。
  Future<void> _showBuiltinPrompt() async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('内置提示词', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: SelectableText(kSystemPrompt,
                style: C.mono.copyWith(fontSize: 12, height: 1.7)),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了', style: TextStyle(fontSize: 13, color: C.blue)),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreBuiltinPrompt() async {
    if (_sys.text.trim().isEmpty) return;
    setState(() => _sys.text = '');
    await _persist();
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _updateNote = '正在问 GitHub…';
    });
    _bump();
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
      if (mounted) {
        setState(() => _checking = false);
        _bump();
      }
    }
  }

  /// 设置页那一行右边写今天花了多少，没记录就留空。
  String get _usageSummary {
    final UsageTotals totals = UsageTotals()
      ..addAll(usageSince(widget.usage.all, usageFrom(1)));
    if (totals.turns == 0) return '';
    return '今天 ${usageText(totals.total)}';
  }

  @override
  Widget build(BuildContext context) {
    final List<_Module> modules = kSettingsModules
        .where((_Module m) => m.key != 'power' || ForegroundTask.supported)
        .toList();
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
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FadeSlideIn(
                child: CardBox(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < modules.length; i += 1) ...<Widget>[
                        if (i > 0) const RuleLine(),
                        _row(modules[i]),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FadeSlideIn(
                delay: const Duration(milliseconds: 70),
                child: CardBox(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      InkWell(
                        onTap: widget.onOpenFiles,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                          child: Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text('临时文件',
                                    style: TextStyle(fontSize: 13.5, color: C.ink)),
                              ),
                              const SizedBox(width: 10),
                              Text(widget.filesSummary, style: C.monoSmall),
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right, size: 16, color: C.grey2),
                            ],
                          ),
                        ),
                      ),
                      const RuleLine(),
                      InkWell(
                        onTap: widget.onOpenUsage,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                          child: Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text('用量',
                                    style: TextStyle(fontSize: 13.5, color: C.ink)),
                              ),
                              const SizedBox(width: 10),
                              Text(_usageSummary, style: C.monoSmall),
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right, size: 16, color: C.grey2),
                            ],
                          ),
                        ),
                      ),
                      const RuleLine(),
                      InkWell(
                        onTap: widget.onOpenAbout,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                          child: Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text('关于 Carbide Shell',
                                    style: TextStyle(fontSize: 13.5, color: C.ink)),
                              ),
                              const SizedBox(width: 10),
                              Text(kAppVersion, style: C.monoSmall),
                              const SizedBox(width: 6),
                              const Icon(Icons.chevron_right, size: 16, color: C.grey2),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '改动即时保存：输入停手半秒后落盘，开关类立即生效。',
                style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 模块清单里的一行：名字、现在的样子、一个箭头。
  Widget _row(_Module module) {
    return InkWell(
      onTap: () => _open(module),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(module.title,
                  style: const TextStyle(fontSize: 13.5, color: C.ink)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                _summary(module.key),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: C.monoSmall,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 16, color: C.grey2),
          ],
        ),
      ),
    );
  }

  /// 每个模块右侧那句现状。看一眼就知道里面是什么。
  String _summary(String key) {
    switch (key) {
      case 'model':
        final String name = _model.text.trim();
        return name.isEmpty ? '还没填' : name;
      case 'approval':
        return _mode == 'autoAll'
            ? '全部放行'
            : _mode == 'askAll'
                ? '全部确认'
                : '写操作确认';
      case 'prompt':
        final String own = _sys.text.trim().isEmpty ? '内置' : '自定';
        return _prompt.text.trim().isEmpty ? own : '$own + 附加';
      case 'talk':
        final String size = _font <= 13.0
            ? '小'
            : _font <= 13.5
                ? '标准'
                : '大';
        return '${_context ~/ 1000}k · $size · ${_stream ? '逐字' : '整段'}';
      case 'net':
        final int n = _domains.text
            .split(RegExp(r'[\s,]+'))
            .where((String d) => d.trim().isNotEmpty)
            .length;
        return n == 0 ? '一个都不许' : '$n 个域名';
      case 'mail':
        if (!_mailOn) return '没开';
        return _mailTo.text.trim().isEmpty ? '没填收件人' : '开着';
      case 'update':
        return _autoUpdate ? '启动时查' : '不自动查';
      case 'power':
        return '通知 ${_styleName(_notifStyle)}';
    }
    return '';
  }

  Future<void> _open(_Module module) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _SettingsModulePage(parent: this, module: module),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  /// 一个模块里的全部控件。子页原样摆出来。
  List<Widget> _moduleBody(String key) {
    switch (key) {
      case 'model':
        return <Widget>[
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
                ),
                RuleField(
                  controller: _steps,
                  label: '每轮步数上限',
                  keyboard: TextInputType.number,
                  onChanged: (_) => _touch(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '密钥只存在本机安全存储，不进对话，也不写日志。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ];
      case 'approval':
        return <Widget>[
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
                _action(
                  '忘掉已批准的写法',
                  '「这一类都批准」的记录一次清空',
                  _forgetApprovals,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '危险命令不因档位放行。定时任务执行时无人确认，除危险命令外一律放行。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ];
      case 'prompt':
        return <Widget>[
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                RuleField(
                  controller: _sys,
                  label: '系统提示词',
                  hint: '留空就是用内置那份。写了就整份替换掉。',
                  minLines: 6,
                  maxLines: 14,
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _prompt,
                  label: '附加指示',
                  hint: '拼在系统提示词后面，比如：回答短一点',
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => _touch(),
                ),
                _action('看看内置提示词', '只读', _showBuiltinPrompt),
                _action(
                  '恢复内置提示词',
                  _sys.text.trim().isEmpty ? '现在就是内置的' : '清掉上面那份',
                  _restoreBuiltinPrompt,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '单个对话可以在对话页顶栏的按钮里另写一份，留空则沿用这里。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ];
      case 'talk':
        return <Widget>[
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _choices<int>(
                  '上下文预算',
                  const <int>[24000, 60000, 120000, 240000],
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
              ],
            ),
          ),
        ];
      case 'net':
        return <Widget>[
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
            child: RuleField(
              controller: _domains,
              label: 'http_request 允许的域名',
              hint: '一行一个，留空表示一个都不许',
              minLines: 4,
              maxLines: 8,
              onChanged: (_) => _touch(),
            ),
          ),
        ];
      case 'update':
        return <Widget>[
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
        ];
      case 'mail':
        return <Widget>[
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _toggle(
                  '发邮件通知',
                  _mailOn,
                  '任务跑完、监听过线时发一封到邮箱',
                  (bool v) => _apply(() => _mailOn = v),
                ),
                const RuleLine(),
                const SizedBox(height: 12),
                RuleField(
                  controller: _mailHost,
                  label: 'SMTP 服务器',
                  hint: 'smtp.qq.com',
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _mailPort,
                  label: '端口',
                  hint: '465',
                  keyboard: TextInputType.number,
                  onChanged: (_) => _touch(),
                ),
                _toggle(
                  '直连加密',
                  _mailSecure,
                  _mailSecure ? '465 一般都要开' : '明文，只适合内网中转',
                  (bool v) => _apply(() => _mailSecure = v),
                ),
                RuleField(
                  controller: _mailUser,
                  label: '账号',
                  hint: 'somebody@qq.com',
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _mailPass,
                  label: '密码或授权码',
                  hint: '留空表示不登录',
                  obscure: true,
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _mailFrom,
                  label: '发件人',
                  hint: 'somebody@qq.com',
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _mailTo,
                  label: '收件人',
                  hint: '多个用逗号分开',
                  onChanged: (_) => _touch(),
                ),
                _toggle(
                  'HTML 排版',
                  _mailHtml,
                  _mailHtml ? '同时带一份纯文本，不认的客户端拿它' : '只发纯文本',
                  (bool v) => _apply(() => _mailHtml = v),
                ),
                const RuleLine(),
                _action('发一封试试', _mailNote.isEmpty ? '按上面的设置发' : _mailNote, _testMail),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '发不出去只影响这一封，任务照常跑完。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ];
      case 'power':
        return <Widget>[
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              children: <Widget>[
                _choices<String>(
                  '通知样式',
                  AppSettings.notifStyles,
                  _notifStyle,
                  _styleName,
                  (String v) => _apply(() => _notifStyle = v),
                ),
                const RuleLine(),
                _action(
                  '系统通知',
                  _notify.ready ? '开着' : '${_notify.text}，点一下打开',
                  _notify.ready ? ForegroundTask.openNotificationSettings : _askNotify,
                ),
                const RuleLine(),
                _action('系统省电设置', '允许后台运行', ForegroundTask.openBatterySettings),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            '长回合与定时任务依赖这个前台服务。系统清掉应用后两者都会停止。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
          const SizedBox(height: 6),
          const Text(
            '通知上那一下「回复」写的就是下一句，发出去跟在这里说一样。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ];
    }
    return const <Widget>[];
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

  /// 发一封试试：按输入框里现在的设置发，不等那 600 毫秒。
  Future<void> _testMail() async {
    setState(() => _mailNote = '正在发…');
    await _persist();
    final Mailer mailer = Mailer(widget.mail);
    if (!mailer.ready) {
      if (mounted) setState(() => _mailNote = widget.mail.value.missing);
      return;
    }
    final SmtpResult result = await mailer.send(
      'Carbide Shell · 测试邮件',
      mailBody(line: '这是一封测试邮件，能收到就说明邮件的设置对了。'),
    );
    if (!mounted) return;
    setState(() => _mailNote = result.ok ? '发出去了' : '没发出去：${result.error}');
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

/// 设置里的一个模块：清单上的一行，也是它子页的标题。
class _Module {
  const _Module(this.key, this.title);

  final String key;
  final String title;
}

const List<_Module> kSettingsModules = <_Module>[
  _Module('model', '模型'),
  _Module('approval', '审批'),
  _Module('prompt', '提示词'),
  _Module('talk', '对话'),
  _Module('net', '网络'),
  _Module('update', '更新'),
  _Module('mail', '邮件'),
  _Module('power', '后台'),
];

/// 一个模块的子页。控制器还在 [SettingsPage] 那一层，这里只是换个地方摆。
class _SettingsModulePage extends StatelessWidget {
  const _SettingsModulePage({required this.parent, required this.module});

  final _SettingsPageState parent;
  final _Module module;

  @override
  Widget build(BuildContext context) {
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
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 19, color: C.ink),
                  ),
                  Text(module.title,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: ValueListenableBuilder<int>(
                      valueListenable: parent._tick,
                      builder: (BuildContext ctx, int value, Widget? child) => Text(
                        parent._saved,
                        style: C.monoSmall.copyWith(
                          color: parent._saved == '已保存' ? C.blue : C.grey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<int>(
                valueListenable: parent._tick,
                builder: (BuildContext ctx, int value, Widget? child) => ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
                  children: parent._moduleBody(module.key),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
