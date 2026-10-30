import 'dart:async';

import 'package:flutter/material.dart';

import '../core/agent.dart';
import '../core/conversation.dart';
import '../core/models.dart';
import '../core/params.dart';
import '../core/poems.dart';
import '../core/policy.dart';
import '../core/pricing.dart';
import '../core/smtp.dart';
import '../core/usage.dart';
import '../data/device.dart';
import '../data/foreground.dart';
import '../data/mail.dart';
import '../data/providers.dart';
import '../data/secrets.dart';
import '../data/settings.dart';
import '../data/tool_groups.dart';
import '../data/usage.dart';
import '../data/update.dart';
import '../version.dart';
import 'components.dart';
import 'motion.dart';
import 'inbox_page.dart';
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
    required this.onOpenEnv,
    required this.envSummary,
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

  /// 环境密钥也是一页，名字和日志在本地，值在安全存储里。
  final VoidCallback onOpenEnv;

  /// 那一行右边写存了几把。
  final String envSummary;

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
  late final TextEditingController _profileName;
  late final TextEditingController _profilePrompt;
  late final TextEditingController _profileUserPrompt;
  late final TextEditingController _steps;
  late final TextEditingController _prompt;
  late final TextEditingController _sys;
  late final TextEditingController _domains;

  /// 这一格被人动过没有。模型加的域名不能被这里的旧文本冲掉。
  bool _domainsTyped = false;

  /// 上一次和这一格对齐时的域名清单，人改的时候只按差异落地。
  List<String> _domainsBase = <String>[];
  late final TextEditingController _priceIn;
  late final TextEditingController _priceCache;
  late final TextEditingController _priceOut;
  late final TextEditingController _peakHolidays;
  late final TextEditingController _peakMakeup;

  String _mode = 'autoRead';
  double _temperature = 0.2;
  double _font = 13.5;
  int _context = 60000;
  bool _stream = true;
  bool _autoUpdate = true;
  bool _autoCompact = true;

  String _picked = '';
  String _saved = '';
  String _updateNote = '';
  bool _checking = false;
  Timer? _debounce;

  /// 现在能不能弹通知，进页时问一次原生。
  NotifyState _notify = const NotifyState();

  /// 每一项扩展要的权限系统给不给。还没问过就不在这个表里。
  final Map<String, bool> _permOk = <String, bool>{};

  /// 通知长什么样：一行、折开、一行一条、像聊天。
  String _notifStyle = 'simple';

  late final TextEditingController _mailHost;
  late final TextEditingController _mailPort;
  late final TextEditingController _mailUser;
  late final TextEditingController _mailPass;
  late final TextEditingController _mailFrom;
  late final TextEditingController _mailTo;
  late final TextEditingController _mailAllowInput;
  late final TextEditingController _mailImapHost;
  late final TextEditingController _mailImapPort;
  String _mailAllowNote = '';
  bool _mailOn = false;
  bool _mailSecure = true;
  bool _mailHtml = true;
  bool _mailImapSecure = true;
  String _mailNote = '';
  String _inboxNote = '';

  /// 子页靠它重画：控制器在这一层，改动也发生在这一层。
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    final AppSettings s = widget.settings.value;
    _profileName = TextEditingController(text: s.active.name);
    _profilePrompt = TextEditingController(text: s.active.prompt);
    _profileUserPrompt = TextEditingController(text: s.active.userPrompt);
    _base = TextEditingController(text: s.baseUrl);
    _model = TextEditingController(text: s.model);
    _key = TextEditingController();
    _steps = TextEditingController(text: '${s.maxSteps}');
    _prompt = TextEditingController(text: s.extraPrompt);
    _sys = TextEditingController(text: s.systemPrompt);
    _domains = TextEditingController(text: s.allowedDomains.join('\n'));
    _domainsBase = List<String>.of(s.allowedDomains);
    _priceIn = TextEditingController();
    _priceCache = TextEditingController();
    _priceOut = TextEditingController();
    _peakHolidays = TextEditingController(text: s.peakHolidays.join('\n'));
    _peakMakeup = TextEditingController(text: s.peakMakeup.join('\n'));
    final SmtpConfig m = widget.mail.value;
    _mailHost = TextEditingController(text: m.host);
    _mailPort = TextEditingController(text: '${m.port}');
    _mailUser = TextEditingController(text: m.user);
    _mailPass = TextEditingController();
    _mailFrom = TextEditingController(text: m.from);
    _mailTo = TextEditingController(text: m.to);
    _mailAllowInput = TextEditingController();
    _mailImapHost = TextEditingController(text: m.imapHost);
    _mailImapPort = TextEditingController(text: '${m.imapPort}');
    widget.mail.addListener(_onMailChanged);
    _mailOn = m.enabled;
    _mailSecure = m.secure;
    _mailHtml = m.html;
    _mailImapSecure = m.imapSecure;
    _mode = s.approvalMode;
    _temperature = s.temperature;
    _font = s.answerFont;
    _context = s.contextChars;
    _stream = s.stream;
    _autoUpdate = s.autoCheckUpdate;
    _autoCompact = s.autoCompact;
    _notifStyle = s.notifStyle;
    _loadKey(s.activeProfile);
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
    _profileName.dispose();
    _profilePrompt.dispose();
    _profileUserPrompt.dispose();
    _steps.dispose();
    _prompt.dispose();
    _sys.dispose();
    _domains.dispose();
    _priceIn.dispose();
    _priceCache.dispose();
    _priceOut.dispose();
    _peakHolidays.dispose();
    _peakMakeup.dispose();
    _mailHost.dispose();
    _mailPort.dispose();
    _mailUser.dispose();
    _mailPass.dispose();
    _mailFrom.dispose();
    _mailTo.dispose();
    _mailAllowInput.dispose();
    _mailImapHost.dispose();
    _mailImapPort.dispose();
    widget.mail.removeListener(_onMailChanged);
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
    // 自己就是那个定时器的回调；别的路径直接叫它的时候也得把待发的定时器收掉，
    // 否则切配置之后那次落盘会把旧输入写进新的那一套。
    _debounce?.cancel();
    widget.settings.value
      ..active.name = _profileName.text.trim()
      ..baseUrl = _base.text.trim()
      ..model = _model.text.trim()
      ..active.prompt = _profilePrompt.text.trim()
      ..active.userPrompt = _profileUserPrompt.text.trim()
      ..maxSteps = _intOf(_steps.text, 12, 1, 200)
      ..temperature = _temperature
      ..approvalMode = _mode
      ..stream = _stream
      ..contextChars = _context
      ..extraPrompt = _prompt.text.trim()
      ..systemPrompt = _sys.text.trim()
      ..answerFont = _font
      ..autoCheckUpdate = _autoUpdate
      ..autoCompact = _autoCompact
      ..notifStyle = _notifStyle
      ..peakHolidays = _linesOf(_peakHolidays.text)
      ..peakMakeup = _linesOf(_peakMakeup.text);
    // 域名这一格只按「人改了什么」落地：模型用 http_allow 加进来的域名，
    // 不能因为这里手一动就被旧文本冲掉。
    if (_domainsTyped) {
      final List<String> typed = _domains.text
          .split(RegExp(r'[\s,]+'))
          .map((String d) => d.trim())
          .where((String d) => d.isNotEmpty)
          .toList();
      final List<String> kept = widget.settings.value.allowedDomains
          .where((String d) => !_domainsBase.contains(d) || typed.contains(d))
          .toList();
      for (final String d in typed) {
        if (!kept.contains(d)) kept.add(d);
      }
      widget.settings.value.allowedDomains = kept;
      _domainsBase = typed;
      _domainsTyped = false;
    }
    // 手填的价：三个数都空着就回到内置价目表。
    final double? pin = double.tryParse(_priceIn.text.trim());
    final double? pcache = double.tryParse(_priceCache.text.trim());
    final double? pout = double.tryParse(_priceOut.text.trim());
    widget.settings.value.active.price
      ..clear()
      ..addAll(<String, Object?>{
        if (pin != null && pin > 0) 'input': pin,
        if (pcache != null && pcache > 0) 'cache': pcache,
        if (pout != null && pout > 0) 'output': pout,
      });
    await widget.settings.save();
    await widget.secrets
        .write(modelSecretKeyFor(widget.settings.value.activeProfile), _key.text.trim());
    widget.mail.value = SmtpConfig(
      enabled: _mailOn,
      host: _mailHost.text.trim(),
      port: _intOf(_mailPort.text, 465, 1, 65535),
      secure: _mailSecure,
      user: _mailUser.text.trim(),
      from: _mailFrom.text.trim(),
      to: _mailTo.text.trim(),
      // 名单是加减出来的，不跟着上面那些输入框走；模型也可能刚改过，读现在这份。
      allowedTo: widget.mail.value.allowedTo,
      html: _mailHtml,
      imapHost: _mailImapHost.text.trim(),
      imapPort: _intOf(_mailImapPort.text, 993, 1, 65535),
      imapSecure: _mailImapSecure,
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

  /// 一行一个的清单：去掉空行，只留 `2026-10-01` 这种写法。
  static List<String> _linesOf(String text) => text
      .split(RegExp(r'[\n,，]+'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

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
            child: Text('知道了', style: TextStyle(fontSize: 13, color: C.blue)),
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
          decoration: BoxDecoration(
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
                              Expanded(
                                child: Text('临时文件',
                                    style: TextStyle(fontSize: 13.5, color: C.ink)),
                              ),
                              const SizedBox(width: 10),
                              Text(widget.filesSummary, style: C.monoSmall),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right, size: 16, color: C.grey2),
                            ],
                          ),
                        ),
                      ),
                      const RuleLine(),
                      InkWell(
                        onTap: widget.onOpenEnv,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text('环境密钥',
                                    style: TextStyle(fontSize: 13.5, color: C.ink)),
                              ),
                              const SizedBox(width: 10),
                              Text(widget.envSummary, style: C.monoSmall),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right, size: 16, color: C.grey2),
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
                              Expanded(
                                child: Text('用量',
                                    style: TextStyle(fontSize: 13.5, color: C.ink)),
                              ),
                              const SizedBox(width: 10),
                              Text(_usageSummary, style: C.monoSmall),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right, size: 16, color: C.grey2),
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
                              Expanded(
                                child: Text('关于 Carbide Shell',
                                    style: TextStyle(fontSize: 13.5, color: C.ink)),
                              ),
                              const SizedBox(width: 10),
                              Text(kAppVersion, style: C.monoSmall),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right, size: 16, color: C.grey2),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
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
                  style: TextStyle(fontSize: 13.5, color: C.ink)),
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
            Icon(Icons.chevron_right, size: 16, color: C.grey2),
          ],
        ),
      ),
    );
  }

  /// 每个模块右侧那句现状。看一眼就知道里面是什么。
  String _summary(String key) {
    switch (key) {
      case 'model':
        final String own = _profileName.text.trim();
        if (own.isNotEmpty) return own;
        final String name = _model.text.trim();
        return name.isEmpty ? '还没填' : name;
      case 'look':
        return switch (widget.settings.value.themeMode) {
          'dark' => '深色',
          'light' => '浅色',
          _ => '跟随系统',
        };
      case 'approval':
        return _mode == 'autoAll'
            ? '全部放行'
            : _mode == 'askAll'
                ? '全部确认'
                : '写操作确认';
      case 'tools':
        final int on = kToolGroups
            .where((ToolGroup g) => widget.settings.value.toolOn(g.id))
            .length;
        return on == 0 ? '都关着' : '开 $on 项';
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
    if (module.key == 'tools') unawaited(_readPerms());
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
        final AppSettings st = widget.settings.value;
        return <Widget>[
          // 一、这套配置本身：名字、地址、密钥
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final ModelProfile p in st.profiles) _profileChip(p),
                    _newProfileChip(),
                  ],
                ),
                const SizedBox(height: 8),
                Text('点一下切过去，切过去的就是默认用的那套。',
                    style: TextStyle(fontSize: 11, color: C.grey, height: 1.5)),
                const SizedBox(height: 14),
                RuleField(
                  controller: _profileName,
                  label: '这套的名字',
                  hint: '自己认得出就行',
                  onChanged: (_) => _touch(),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kLlmPresets.map(_presetChip).toList(),
                ),
                if (_picked.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 9),
                  Text(_picked,
                      style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.5)),
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
                RuleField(
                  controller: _steps,
                  label: '每轮步数上限',
                  keyboard: TextInputType.number,
                  onChanged: (_) => _touch(),
                ),
                _configCheck(),
                const RuleLine(),
                _action('复制一套', '提示词、参数、报价一起拷，密钥不拷', _copyProfile),
                if (st.profiles.length > 1)
                  _action('删掉这套配置', '地址与密钥一起清掉', _deleteProfile),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 二、参数：值、来源、锁、范围
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final ParamSpec spec in kParamSpecs) _paramRow(spec),
                const RuleLine(),
                _toggle(
                  '允许 AI 调节参数',
                  st.aiTune,
                  '它只能提，提了还要你点批准；锁住的参数它改不动',
                  (bool v) => _apply(() => st.aiTune = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 三、计价：手填的价盖住内置价目表
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(_priceLine(st.active),
                    style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6)),
                const SizedBox(height: 12),
                RuleField(
                  controller: _priceIn,
                  label: '输入价（元 / 百万 token）',
                  hint: '没命中缓存的那部分',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _priceCache,
                  label: '缓存命中价（元 / 百万 token）',
                  hint: '不确定就留空，按输入价算',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _priceOut,
                  label: '输出价（元 / 百万 token）',
                  hint: '模型的输出报价',
                  keyboard: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => _touch(),
                ),
                _action('用内置价目表', '清掉上面手填的三个数', _clearPrice),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // 四、提示词：跟着这套走
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                RuleField(
                  controller: _profilePrompt,
                  label: '这套绑定的提示词',
                  hint: '切到这套就换上它；留空就是设置里那份',
                  minLines: 3,
                  maxLines: 8,
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _profileUserPrompt,
                  label: '只给这套写的一份',
                  hint: '优先级最高；留空就用上面那份',
                  minLines: 3,
                  maxLines: 8,
                  onChanged: (_) => _touch(),
                ),
                _action('看看内置提示词', '只读', _showBuiltinPrompt),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '提示词次序：对话自己写的 > 这里「只给这套写的一份」> 「这套绑定的」> 设置里的全局提示词 > 内置那份。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
          const SizedBox(height: 6),
          Text(
            '密钥只存在本机安全存储，不进对话，也不写日志。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ];
      case 'look':
        return <Widget>[
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _choices<String>(
                  '颜色',
                  AppSettings.themeModes,
                  widget.settings.value.themeMode,
                  (String v) => switch (v) {
                    'dark' => '深色',
                    'light' => '浅色',
                    _ => '跟随系统',
                  },
                  (String v) => _apply(() => widget.settings.value.themeMode = v),
                  last: true,
                ),
              ],
            ),
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
          Text(
            '危险命令不因档位放行。定时任务执行时无人确认，除危险命令外一律放行。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ];
      case 'tools':
        return <Widget>[
          if (!const PhoneDevice().supported)
            Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '这些扩展只在安卓上有，这台机器上开不开都一样。',
                style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
              ),
            ),
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final ToolGroup g in kToolGroups) _toolRow(g),
                _action(
                  '打开系统的应用设置',
                  '权限被拒过之后，要在那里改',
                  openAppSettings,
                ),
                if (const PhoneDevice().supported) ...<Widget>[
                  _action(
                    '打开通知读取设置',
                    '系统里那一项叫「通知使用权」',
                    const PhoneDevice().openNotificationAccess,
                  ),
                  _action(
                    '打开使用情况访问设置',
                    '系统里那一项叫「使用情况访问」',
                    const PhoneDevice().openUsageAccess,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '开着的那几项才进模型的工具清单，关着的它看不见。改完下一句话就生效。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
          const SizedBox(height: 6),
          Text(
            '定位、联系人、短信在打开时向系统要一次权限。工具不会自己弹框，也不会替你发消息。',
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
          Text(
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
                _toggle(
                  '长了自动压一次',
                  _autoCompact,
                  '记录超过预算几倍时，前面的收成一段摘要',
                  (bool v) => _apply(() => _autoCompact = v),
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
                const RuleLine(),
                _toggle(
                  '等待时读一首诗',
                  widget.settings.value.poemOn,
                  '每次只一首，随机挑，不连着重复',
                  (bool v) => _apply(() => widget.settings.value.poemOn = v),
                ),
                _choices<int>(
                  '隔多久换一首',
                  const <int>[10, 20, 30, 45, 60],
                  widget.settings.value.poemEvery,
                  (int v) => '$v 秒',
                  (int v) => _apply(
                      () => widget.settings.value.poemEvery = clampPoemEvery(v)),
                ),
                _toggle(
                  '右侧问候语',
                  widget.settings.value.greetOn,
                  '宽屏时在对话右边写几行，窄屏不占地方',
                  (bool v) => _apply(() => widget.settings.value.greetOn = v),
                ),
                _toggle(
                  '问候语带峰谷提示',
                  widget.settings.value.greetPeak,
                  '用 DeepSeek 时附一句现在是不是谷时',
                  (bool v) => _apply(() => widget.settings.value.greetPeak = v),
                ),
                const RuleLine(),
                RuleField(
                  controller: _peakHolidays,
                  label: '法定节假日（北京时间，一行一个）',
                  hint: '2026-10-01',
                  minLines: 2,
                  maxLines: 6,
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _peakMakeup,
                  label: '调休上班的周末（一行一个）',
                  hint: '2026-10-11',
                  minLines: 1,
                  maxLines: 4,
                  onChanged: (_) => _touch(),
                ),
                Text(
                  '内置的只有 2025 年那一年的官方排期。新的排期公布后填在上面两格，'
                  '这些日子 DeepSeek 全天按谷时算，调休上班的周末也一样。',
                  style: TextStyle(fontSize: 11, color: C.grey, height: 1.6),
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
              onChanged: (_) {
                _domainsTyped = true;
                _touch();
              },
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
                _mailAllowlist(),
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
          CardBox(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('收信',
                    style: TextStyle(
                        fontSize: 12.5, color: C.ink, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('账号和密码跟上面那两行用同一份，这里只填服务器。',
                    style: TextStyle(fontSize: 11, color: C.grey, height: 1.5)),
                const SizedBox(height: 10),
                RuleField(
                  controller: _mailImapHost,
                  label: 'IMAP 服务器',
                  hint: 'imap.qq.com',
                  onChanged: (_) => _touch(),
                ),
                RuleField(
                  controller: _mailImapPort,
                  label: '端口',
                  hint: '993',
                  keyboard: TextInputType.number,
                  onChanged: (_) => _touch(),
                ),
                _toggle(
                  '直连加密',
                  _mailImapSecure,
                  _mailImapSecure ? '993 一般都要开' : '明文，只适合内网',
                  (bool v) => _apply(() => _mailImapSecure = v),
                ),
                const RuleLine(),
                _action(
                  '收件箱',
                  _mailImapHost.text.trim().isEmpty ? '先填服务器' : '看最近 20 封',
                  _openInbox,
                ),
                const RuleLine(),
                _action('试一下收信', _inboxNote.isEmpty ? '只登录，不拉信' : _inboxNote, _testInbox),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '发不出去只影响这一封，任务照常跑完。收信是只读的：不标已读，也不下载附件。',
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
                const RuleLine(),
                _action('通知诊断', '看这台机器认哪一步', _showNotifDiag),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '长回合与定时任务依赖这个前台服务。系统清掉应用后两者都会停止。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
          const SizedBox(height: 6),
          Text(
            '通知上那一下「回复」写的就是下一句，发出去不用打开应用。',
            style: TextStyle(fontSize: 11, color: C.grey, height: 1.7),
          ),
        ];
    }
    return const <Widget>[];
  }

  /// 读一套配置自己的密钥。进页和切配置都走这里。
  Future<void> _loadKey(String profileId) async {
    final String key = await widget.secrets.read(modelSecretKeyFor(profileId));
    if (!mounted) return;
    setState(() => _key.text = key);
  }

  /// 先把手上这套写回去，再把另一套读到输入框里。
  Future<void> _switchProfile(String id) async {
    _debounce?.cancel();
    final AppSettings s = widget.settings.value;
    if (id == s.activeProfile) return;
    await _persist();
    s.switchProfile(id);
    _fillProfileFields(s);
    await widget.settings.save();
    await _loadKey(s.activeProfile);
    if (!mounted) return;
    _setSaved('已切换');
  }

  /// 新建一套空的，地址与模型名都不预填。
  Future<void> _newProfile() async {
    _debounce?.cancel();
    await _persist();
    final AppSettings s = widget.settings.value;
    s.addProfile();
    _profileName.text = '';
    _base.text = '';
    _model.text = '';
    _key.text = '';
    _picked = '';
    _profilePrompt.text = '';
    _profileUserPrompt.text = '';
    await widget.settings.save();
    if (!mounted) return;
    _setSaved('新建了一套');
  }

  /// 删掉当前这套：清单和它的密钥一起清。只剩一套时不动。
  Future<void> _deleteProfile() async {
    _debounce?.cancel();
    final AppSettings s = widget.settings.value;
    if (s.profiles.length <= 1) return;
    final String gone = s.activeProfile;
    if (!s.removeProfile(gone)) return;
    await widget.secrets.delete(modelSecretKeyFor(gone));
    _fillProfileFields(s);
    await widget.settings.save();
    await _loadKey(s.activeProfile);
    if (!mounted) return;
    _setSaved('删掉了这一套');
  }

  /// 芯片上写什么：正在改名字的那套跟着输入框走，其余的写存下的名字。
  String _profileLabel(ModelProfile p) {
    if (p.id == widget.settings.value.activeProfile) {
      final String typing = _profileName.text.trim();
      if (typing.isNotEmpty) return typing;
    }
    return p.label;
  }

  /// 这套配置到底能不能用：地址、模型名、密钥三样。
  Widget _configCheck() {
    final List<String> bad = <String>[];
    final String url = _base.text.trim();
    final String model = _model.text.trim();
    if (url.isEmpty) {
      bad.add('还没填地址');
    } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
      bad.add('地址要以 http:// 或 https:// 开头');
    }
    if (model.isEmpty) bad.add('还没填模型名');
    if (_key.text.trim().isEmpty) bad.add('还没填密钥（本地模型可以空着）');
    final bool ready = bad.isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5, right: 7),
            decoration: BoxDecoration(
              color: ready ? C.blue : C.rule2,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Text(
              ready ? '这一套填好了，切过去就能用。' : bad.join('；'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.6,
                color: ready ? C.grey : C.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 一个参数一行：值（点开改）、谁改的、锁、范围、恢复。
  Widget _paramRow(ParamSpec spec) {
    final AppSettings s = widget.settings.value;
    final ModelProfile p = s.active;
    final ParamState? state = p.paramState(spec.key);
    final double value = p.paramValue(spec.key);
    final ParamRange range = s.paramRange(spec.key);
    final bool locked = state?.locked ?? false;
    final String who = <String>[
      state?.sourceLabel ?? '默认',
      if ((state?.reason ?? '').isNotEmpty) state!.reason,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(spec.label, style: TextStyle(fontSize: 13, color: C.ink)),
                    const SizedBox(height: 3),
                    Text(who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: C.grey, height: 1.4)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _editParamValue(spec),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: C.paper2,
                    borderRadius: BorderRadius.circular(C.radiusSmall),
                  ),
                  child: Text(spec.format(value),
                      style: C.monoSmall.copyWith(color: C.ink, fontSize: 11.5)),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _toggleParamLock(spec, !locked),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: locked ? C.blueSoft : C.paper2,
                    borderRadius: BorderRadius.circular(C.radiusSmall),
                  ),
                  child: Icon(locked ? Icons.lock : Icons.lock_open,
                      size: 14, color: locked ? C.blue : C.grey),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text('允许 ${range.text}\u3000${locked ? '锁着，AI 改不动' : 'AI 可以提，批准后生效'}',
                    style: TextStyle(fontSize: 10.5, color: C.grey2, height: 1.4)),
              ),
              _miniLink('改范围', () => _editParamRange(spec)),
              const SizedBox(width: 10),
              _miniLink('恢复默认', () => _resetParam(spec)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniLink(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text(label, style: TextStyle(fontSize: 10.5, color: C.blue)),
    );
  }

  /// 调一个数字的小对话框。返回 null 表示没改。
  Future<String?> _numberDialog({
    required String title,
    required String hint,
    required List<TextEditingController> fields,
    required List<String> labels,
  }) async {
    final String? done = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(hint, style: TextStyle(fontSize: 11.5, color: C.grey, height: 1.6)),
            const SizedBox(height: 10),
            for (int i = 0; i < fields.length; i += 1) ...<Widget>[
              TextField(
                controller: fields[i],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(labelText: labels[i]),
              ),
              if (i < fields.length - 1) const SizedBox(height: 8),
            ],
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('取消', style: TextStyle(fontSize: 13, color: C.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('ok'),
            child: Text('保存', style: TextStyle(fontSize: 13, color: C.blue)),
          ),
        ],
      ),
    );
    return done;
  }

  /// 自己填一个参数值。锁不影响用户自己改，来源记成手动。
  Future<void> _editParamValue(ParamSpec spec) async {
    final AppSettings s = widget.settings.value;
    final ModelProfile p = s.active;
    final ParamRange range = s.paramRange(spec.key);
    final TextEditingController field =
        TextEditingController(text: spec.format(p.paramValue(spec.key)));
    final String? done = await _numberDialog(
      title: spec.label,
      hint: '允许 ${range.text}。填过之后这套就用这个值，AI 的提议要你批准才会覆盖它。',
      fields: <TextEditingController>[field],
      labels: <String>[spec.label],
    );
    final String raw = field.text;
    field.dispose();
    if (done == null || !mounted) return;
    final double? value = double.tryParse(raw.trim());
    if (value == null) {
      _setSaved('要填一个数字');
      return;
    }
    final ParamEdit edit = applyParam(
      p.params,
      key: spec.key,
      value: value,
      range: range,
      byAi: false,
      reason: '自己填的',
    );
    if (!edit.ok) {
      _setSaved(edit.text);
      return;
    }
    setState(() {});
    await _persist();
    _setSaved(edit.text);
  }

  /// 改这一个参数允许落在什么范围。只能往出厂范围里收窄。
  Future<void> _editParamRange(ParamSpec spec) async {
    final AppSettings s = widget.settings.value;
    final ParamRange range = s.paramRange(spec.key);
    final TextEditingController low = TextEditingController(text: '${range.low}');
    final TextEditingController high = TextEditingController(text: '${range.high}');
    final String? done = await _numberDialog(
      title: '${spec.label}的允许范围',
      hint: '出厂范围是 ${spec.span}，只能往里收。AI 的值落在这个范围外会被拒绝。',
      fields: <TextEditingController>[low, high],
      labels: <String>['最小', '最大'],
    );
    final double? a = double.tryParse(low.text.trim());
    final double? b = double.tryParse(high.text.trim());
    low.dispose();
    high.dispose();
    if (done == null || !mounted) return;
    if (a == null || b == null || a >= b) {
      _setSaved('范围要两个数，小的在前面');
      return;
    }
    s.paramRanges[spec.key] = <double>[a, b];
    setState(() {});
    await _persist();
    _setSaved('范围改成 ${s.paramRange(spec.key).text}');
  }

  Future<void> _toggleParamLock(ParamSpec spec, bool locked) async {
    setParamLock(widget.settings.value.active.params, key: spec.key, locked: locked);
    setState(() {});
    await _persist();
    _setSaved(locked ? '${spec.label}锁上了，AI 改不动' : '${spec.label}解锁了');
  }

  Future<void> _resetParam(ParamSpec spec) async {
    resetParam(widget.settings.value.active.params, key: spec.key);
    setState(() {});
    await _persist();
    _setSaved('${spec.label}回到 ${spec.format(spec.fallback)}');
  }

  /// 把手上这套设成默认。
  /// 复制一份：提示词、参数、报价一起拷，密钥不拷（新的一套自己填）。
  Future<void> _copyProfile() async {
    _debounce?.cancel();
    await _persist();
    final AppSettings s = widget.settings.value;
    final String from = s.activeProfile;
    final ModelProfile copy = s.duplicateProfile(from);
    await widget.settings.save();
    _fillProfileFields(s);
    await _loadKey(copy.id);
    if (!mounted) return;
    setState(() {});
    _setSaved('复制成了 ${copy.label}，密钥要自己填');
  }

  /// 这套配置的价从哪儿来，一句话说清。
  String _priceLine(ModelProfile p) {
    final PriceQuote quote = quotePrice(manual: p.price, model: p.model);
    if (!quote.known) {
      return '还没价：手填三个数，或者把模型名写成内置价目表里有的那些（'
          '${kPriceBook.map((PriceEntry e) => e.match).join(' / ')}）。';
    }
    final String peak = quote.peakValley ? '，谷时半价' : '';
    return '现在按${quote.sourceLabel}的价算：${quote.price!.oneLine}$peak。';
  }

  /// 回到内置价目表。
  Future<void> _clearPrice() async {
    _priceIn.text = '';
    _priceCache.text = '';
    _priceOut.text = '';
    setState(() {});
    await _persist();
    _setSaved('改回内置价目表');
  }

  /// 把当前这套的提示词读进输入框。切配置、新建、删除之后都要叫一次。
  void _fillProfileFields(AppSettings s) {
    _profileName.text = s.active.name;
    _base.text = s.baseUrl;
    _model.text = s.model;
    _profilePrompt.text = s.active.prompt;
    _profileUserPrompt.text = s.active.userPrompt;
    final String pin = '${s.active.price['input'] ?? ''}';
    final String pcache = '${s.active.price['cache'] ?? ''}';
    final String pout = '${s.active.price['output'] ?? ''}';
    _priceIn.text = pin.isEmpty || pin == 'null' ? '' : pin;
    _priceCache.text = pcache.isEmpty || pcache == 'null' ? '' : pcache;
    _priceOut.text = pout.isEmpty || pout == 'null' ? '' : pout;
    _picked = '';
  }

  /// 一套配置的芯片，点一下就切过去。
  Widget _profileChip(ModelProfile p) {
    final bool on = p.id == widget.settings.value.activeProfile;
    return GestureDetector(
      onTap: () => _switchProfile(p.id),
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
          _profileLabel(p),
          style: TextStyle(fontSize: 12, color: on ? C.onAccent : C.ink),
        ),
      ),
    );
  }

  Widget _newProfileChip() {
    return GestureDetector(
      onTap: _newProfile,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: C.rule2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.add, size: 14, color: C.grey),
            SizedBox(width: 4),
            Text('新建一套', style: TextStyle(fontSize: 12, color: C.ink)),
          ],
        ),
      ),
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
        child: Text(p.name, style: TextStyle(fontSize: 12, color: C.ink)),
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
          Text(label, style: TextStyle(fontSize: 11.5, color: C.grey)),
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
                    style: TextStyle(fontSize: 12, color: on ? C.onAccent : C.ink),
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

  /// 打开收件箱。先把这一页的输入盘一次，不然刚填的 IMAP 地址还没落盘。
  Future<void> _openInbox() async {
    await _persist();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => InboxPage(mail: widget.mail)),
    );
    if (!mounted) return;
    setState(() {});
  }

  /// 只登录，不拉任何一封：能连上就说明服务器、端口、授权码都对。
  Future<void> _testInbox() async {
    setState(() => _inboxNote = '正在连…');
    await _persist();
    final String note = await widget.mail.testInbox();
    if (!mounted) return;
    setState(() => _inboxNote = note);
  }

  /// 名单存了一次就重画一次：模型在后台加了一个地址，这一页也得跟着变，
  /// 否则下一次落盘会把手里那份旧的写回去。
  void _onMailChanged() {
    if (!mounted) return;
    setState(() {});
    _bump();
  }

  /// 「AI 能发给谁」那一份名单：一条一行，右边一个叉；下面一个输入框加一条。
  ///
  /// 收件人那一行带来的地址也在这里露脸，但它属于那行输入框，在这一页删不掉。
  Widget _mailAllowlist() {
    final SmtpConfig m = widget.mail.value;
    final List<String> list = m.allowed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('AI 能发给谁', style: TextStyle(fontSize: 11.5, color: C.grey)),
            const Spacer(),
            Text('${list.length} 个', style: C.monoSmall),
          ],
        ),
        const SizedBox(height: 8),
        if (list.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: C.paper2,
              borderRadius: BorderRadius.circular(C.radiusSmall),
            ),
            child: Text(
              '名单是空的。下面加一个，模型就能发给它。',
              style: TextStyle(fontSize: 12, color: C.grey, height: 1.5),
            ),
          )
        else
          for (final String address in list)
            _mailAllowRow(address, removable: m.listedAsExtra(address)),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                decoration: BoxDecoration(
                  color: C.card,
                  borderRadius: BorderRadius.circular(C.radiusSmall),
                  border: Border.all(color: _mailAllowNote.isEmpty ? C.rule : C.danger),
                ),
                child: TextField(
                  controller: _mailAllowInput,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addAllowed(),
                  style: C.mono.copyWith(fontSize: 13),
                  decoration: const InputDecoration(hintText: 'somebody@example.com'),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _addAllowed,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: C.blue,
                  borderRadius: BorderRadius.circular(C.radiusSmall),
                ),
                child: Text('加上', style: TextStyle(fontSize: 13, color: C.onAccent)),
              ),
            ),
          ],
        ),
        if (_mailAllowNote.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(_mailAllowNote,
              style: TextStyle(fontSize: 11.5, color: C.danger, height: 1.4)),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _mailAllowRow(String address, {required bool removable}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        height: 40,
        padding: const EdgeInsets.only(left: 12, right: 2),
        decoration: BoxDecoration(
          color: C.paper2,
          borderRadius: BorderRadius.circular(C.radiusSmall),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: C.mono.copyWith(fontSize: 12.5),
              ),
            ),
            if (removable)
              IconButton(
                onPressed: () => _removeAllowed(address),
                icon: Icon(Icons.close, size: 15, color: C.grey),
                tooltip: '从名单里删掉',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text('默认收件人',
                    style: C.monoSmall.copyWith(fontSize: 10)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _addAllowed() async {
    final String raw = _mailAllowInput.text.trim();
    final String? problem = addressProblem(raw);
    if (problem != null) {
      setState(() => _mailAllowNote = problem);
      return;
    }
    if (widget.mail.value.canSendTo(raw)) {
      setState(() => _mailAllowNote = '$raw 已经在名单里了');
      return;
    }
    _mailAllowInput.clear();
    setState(() => _mailAllowNote = '');
    await _setAllowed(<String>[...widget.mail.value.allowedTo, raw]);
  }

  Future<void> _removeAllowed(String address) async {
    final String a = address.trim().toLowerCase();
    final List<String> next = widget.mail.value.allowedTo
        .where((String e) => e.trim().toLowerCase() != a)
        .toList();
    setState(() => _mailAllowNote = '');
    await _setAllowed(next);
  }

  /// 加一条删一条就存一次，不等那 600 毫秒：这是两个离散的动，不存在打到一半的中间态。
  Future<void> _setAllowed(List<String> list) async {
    await widget.mail.setAllowed(list);
    if (!mounted) return;
    setState(() {});
    _setSaved('已保存');
  }

  /// 一项扩展一行：名字、能干什么、系统给不给权限。
  Widget _toolRow(ToolGroup g) {
    final bool on = widget.settings.value.toolOn(g.id);
    String note = g.note;
    final DevicePerm? perm = g.perm;
    if (perm != null) {
      final bool? ok = _permOk[g.id];
      if (ok == false) {
        note = '$note。系统没给${perm.label}权限，这一项用不了';
      } else if (ok == true) {
        note = '$note。系统已允许';
      }
    }
    return _toggle(g.name, on, note, (bool v) => _setTool(g, v));
  }

  /// 打开一项扩展。要权限的先去要一次，系统不给就不打开。
  Future<void> _setTool(ToolGroup g, bool on) async {
    if (!on) {
      _apply(() => widget.settings.value.setTool(g.id, false));
      return;
    }
    final DevicePerm? perm = g.perm;
    if (perm != null) {
      const DeviceApi phone = PhoneDevice();
      bool ok = _permOk[g.id] ?? false;
      try {
        if (!ok) ok = await phone.has(perm);
        if (!ok) ok = await phone.request(perm);
      } on DeviceError catch (e) {
        if (!mounted) return;
        _setSaved(e.message);
        return;
      }
      if (!mounted) return;
      setState(() => _permOk[g.id] = ok);
      if (!ok) {
        _setSaved('系统没给${perm.label}权限，这一项没打开');
        return;
      }
    }
    _apply(() => widget.settings.value.setTool(g.id, true));
  }

  /// 进扩展那一页时，先问一遍各项权限现在给不给。
  Future<void> _readPerms() async {
    const DeviceApi phone = PhoneDevice();
    if (!phone.supported) return;
    for (final ToolGroup g in kToolGroups) {
      final DevicePerm? perm = g.perm;
      if (perm == null) continue;
      try {
        final bool ok = await phone.has(perm);
        if (!mounted) return;
        setState(() => _permOk[g.id] = ok);
        // 打开着的子页只跟着 _tick 重画，所以要 bump 一下。
        _bump();
      } on DeviceError {
        // 问不出来就先不写，界面上也不多说一句。
      }
    }
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
                Text(label, style: TextStyle(fontSize: 13, color: C.ink)),
                const SizedBox(height: 3),
                Text(note, style: TextStyle(fontSize: 11, color: C.grey, height: 1.4)),
              ],
            ),
          ),
          ToggleKnob(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  /// 把三条通知状态挨着走一遍，好让人自己看一眼岛上认不认这几种。
  ///
  /// 两秒跑着、三秒等人批准、再留几秒「已完成」，然后自己收掉。
  Future<void> _tryIslandStates() async {
    await ForegroundTask.begin('试一遍 · 第 1/3 步 · 跑着', state: 'run');
    await Future<void>.delayed(const Duration(seconds: 2));
    await ForegroundTask.update('试一遍 · 第 2/3 步 · 等你确认', state: 'wait');
    await Future<void>.delayed(const Duration(seconds: 3));
    await ForegroundTask.complete('试一遍 · 已完成',
        residual: !ForegroundTask.visible);
  }

  /// 这台机器到底缺哪一环：问原生要几行，摆成一个对话框。
  Future<void> _showNotifDiag() async {
    final List<String> lines = await ForegroundTask.diag();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('通知诊断',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (final String line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(line,
                      style: C.monoSmall.copyWith(fontSize: 11.5, color: C.ink)),
                ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              unawaited(_tryIslandStates());
            },
            child: Text('试一遍三种状态',
                style: TextStyle(fontSize: 13, color: C.blue)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('知道了', style: TextStyle(fontSize: 13, color: C.blue)),
          ),
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
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: C.ink))),
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
            Icon(Icons.chevron_right, size: 16, color: C.grey2),
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
  _Module('look', '外观'),
  _Module('model', '模型'),
  _Module('approval', '审批'),
  _Module('tools', '扩展'),
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
    // 这一页是推上来的路由：换色板时外壳会重画，它靠听 C.revision 自己重画。
    return ValueListenableBuilder<int>(
      valueListenable: C.revision,
      builder: (BuildContext palette, int _, Widget? __) => Scaffold(
        backgroundColor: C.paper,
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: C.card,
                  border: Border(bottom: BorderSide(color: C.rule)),
                ),
                child: Row(
                  children: <Widget>[
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back, size: 19, color: C.ink),
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
      ),
    );
  }
}
