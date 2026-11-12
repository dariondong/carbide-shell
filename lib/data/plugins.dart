import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../core/plugin.dart';
import '../tools/ssh_tools.dart';
import 'hosts.dart';
import 'plugin_runtime.dart';

/// 远程插件：装在一台用户指定的机器上，手机只留清单。
///
/// 手机上没有 npm、没有 node，也开不了子进程，所以 dsh 那些工具插件在
/// 手机上装不了。这一层就是把「装」和「跑」挪到一台代理机上，手机这边
/// 只做三件事：把清单拉回来、把开关记下来、把调用发出去。
///
/// 代理机不需要开端口、不需要常驻服务、不需要装 dsh：走的还是这条 SSH
/// 连接，代理机上只多了一个 Node 和一个不到 20K 的桥脚本。
///
/// 传文件一律走 base64 管道，不碰 SFTP——少一个子系统要维护，也省掉
/// 远端目录存不存在这种问题。
class PluginStore extends ChangeNotifier {
  PluginStore({
    required this.file,
    required this.hosts,
    required this.pool,
  });

  final File file;
  final HostStore hosts;
  final SshPool pool;

  /// 用哪台主机当代理。空表示还没选。
  String proxyHostId = '';

  /// 装到代理机的哪个目录。空表示默认 `$HOME/.carbide/plugins`。
  String proxyRoot = '';

  final Map<String, PluginManifest> _byId = <String, PluginManifest>{};

  /// 最近一次体检的结果，界面上照着显示。
  ProxyStatus status = const ProxyStatus();

  /// 正在忙的时候说一句，界面好显示。
  String busy = '';

  /// 太老的 node 跑不动 dsh-tools。装的时候就钉死这个版本。
  static const String _nodeVersion = 'v24.11.0';

  List<PluginManifest> get plugins => _byId.values.toList(growable: false);

  PluginManifest? byId(String id) => _byId[id];

  bool get ready => proxyHostId.trim().isNotEmpty;

  HostEntry? get proxyHost {
    final String id = proxyHostId.trim();
    if (id.isEmpty) return null;
    return hosts.byId(id);
  }

  /// 开着的插件一共带进来多少个工具。
  int get toolCount =>
      plugins.where((PluginManifest p) => p.on).fold<int>(0, (int n, PluginManifest p) => n + p.tools.length);

  // ---------------------------------------------------------------- 落盘

  Future<void> load() async {
    if (!file.existsSync()) return;
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        final Map<String, Object?> json = Map<String, Object?>.from(decoded);
        proxyHostId = '${json['proxyHostId'] ?? ''}';
        proxyRoot = '${json['proxyRoot'] ?? ''}';
        final Object? raw = json['plugins'];
        if (raw is List) {
          for (final Object? e in raw) {
            if (e is! Map) continue;
            final PluginManifest m = PluginManifest.fromJson(Map<String, Object?>.from(e));
            if (m.id.isNotEmpty) _byId[m.id] = m;
          }
        }
      }
    } catch (_) {
      // 文件坏了就当没装过，别挡住应用启动。
    }
  }

  Future<void> save() async {
    file.parent.createSync(recursive: true);
    final String text = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'proxyHostId': proxyHostId,
      'proxyRoot': proxyRoot,
      'plugins': plugins.map((PluginManifest p) => p.toJson()).toList(),
    });
    await file.writeAsString(text);
  }

  Future<void> rememberProxy(String hostId, {String? root}) async {
    proxyHostId = hostId;
    if (root != null) proxyRoot = root;
    await save();
    notifyListeners();
  }

  /// 开或关一个插件。关掉的只是不进模型清单，包和清单都留着。
  Future<void> setOn(String id, bool on) async {
    final PluginManifest? m = _byId[id];
    if (m == null) return;
    _byId[id] = m.copyWith(on: on);
    await save();
    notifyListeners();
    if (on) await refreshSkills(fresh: true);
  }

  /// 改一个工具的风险档。插件本身没有这个概念，默认按名字猜，猜错了能改。
  /// 改插件配置。配置会影响装配，所以改完立刻重新收割一次清单。
  Future<void> setConfig(String id, String config) async {
    final PluginManifest? m = _byId[id];
    if (m == null) return;
    final String own = config.trim();
    if (m.config == own) return;
    _byId[id] = m.copyWith(config: own);
    try {
      // 先拿新配置收割一次：不对就当场抛，别把坏配置留在身上，
      // 否则会变成「装得上、工具清单却是空的」这种最难查的状态。
      await refresh(id);
    } catch (e) {
      _byId[id] = m;
      await save();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setToolRisk(String id, String toolName, String risk) async {
    final PluginManifest? m = _byId[id];
    if (m == null) return;
    final List<PluginToolSpec> next = m.tools
        .map((PluginToolSpec t) => t.name == toolName ? t.copyWith(risk: risk) : t)
        .toList(growable: false);
    _byId[id] = m.copyWith(tools: next);
    await save();
    notifyListeners();
  }

  // ---------------------------------------------------------------- 路径

  /// 目录在 shell 里的写法。
  ///
  /// 默认值里带着 `$HOME`，必须让 shell 去展开，不能整个焊死在单引号里——
  /// 否则 node 会真的建一个名叫 `$HOME` 的目录。
  String get _rootExpr {
    final String own = proxyRoot.trim();
    if (own.isEmpty) return r'"$HOME/.carbide/plugins"';
    if (own == '~') return r'"$HOME"';
    if (own.startsWith('~/')) return '"\$HOME/${own.substring(2)}"';
    return _q(own);
  }

  String get _workExpr => '$_rootExpr/work';

  String get _nodeExpr => '$_rootExpr/node/bin/node';

  String get _engineExpr => '$_rootExpr/carbide-plugin.mjs';

  String _q(String s) => "'${s.replaceAll("'", r"'\''")}'";

  /// 往命令里塞一份可能带引号的东西：先 base64，再单引号包起来。
  String _b64(String text) => _q(base64Encode(utf8.encode(text)));

  String _bootstrapScript() {
    const String tpl = r'''
set -u
ROOT=__ROOT__
mkdir -p "$ROOT" "$ROOT/work"
if [ ! -x "$ROOT/node/bin/node" ]; then
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64|amd64) NARCH=x64 ;;
    aarch64|arm64) NARCH=arm64 ;;
    *) echo "CARBIDE_ARCH_UNSUPPORTED=$ARCH" >&2; exit 2 ;;
  esac
  TMP=$(mktemp -d)
  URL="https://nodejs.org/dist/__NODEVER__/node-__NODEVER__-linux-$NARCH.tar.xz"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --max-time 300 -o "$TMP/n.tar.xz" "$URL" || { echo "CARBIDE_NODE_DOWNLOAD_FAILED" >&2; exit 3; }
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$TMP/n.tar.xz" "$URL" || { echo "CARBIDE_NODE_DOWNLOAD_FAILED" >&2; exit 3; }
  else
    echo "CARBIDE_NO_CURL" >&2; exit 4
  fi
  tar xf "$TMP/n.tar.xz" -C "$TMP" || { echo "CARBIDE_NODE_UNPACK_FAILED" >&2; exit 5; }
  rm -rf "$ROOT/node"
  mv "$TMP/node-__NODEVER__-linux-$NARCH" "$ROOT/node"
  rm -rf "$TMP"
fi
echo "CARBIDE_NODE=$("$ROOT/node/bin/node" -v)"
exit 0
''';
    return tpl.replaceAll('__ROOT__', _rootExpr).replaceAll('__NODEVER__', _nodeVersion);
  }

  // ---------------------------------------------------------------- 部署

  /// 部署：把 node 和桥放到代理机上。可以反复点，已经就位就跳过。
  Future<ProxyStatus> deploy() async {
    final HostEntry? host = proxyHost;
    if (host == null) {
      status = const ProxyStatus(error: '还没选代理服务器。');
      notifyListeners();
      return status;
    }
    busy = '部署中';
    notifyListeners();
    try {
      final _Run boot = await _run(host, _bootstrapScript(), timeout: const Duration(seconds: 400));
      if (boot.code != 0) {
        status = ProxyStatus(error: _explain(boot, 'node 装不上'));
        return status;
      }
      final _Run put = await _run(host, _putFile(_engineExpr, kPluginEngine));
      if (put.code != 0) {
        status = ProxyStatus(error: _explain(put, '桥脚本放不上去'));
        return status;
      }
      final _Run probe = await _run(host, _engineCommand('probe'));
      final Map<String, Object?> json = _lastJson(probe.out);
      if (json['ok'] != true) {
        status = ProxyStatus(error: _explain(probe, '桥跑不起来'));
        return status;
      }
      status = ProxyStatus(
        ok: true,
        node: '${json['node'] ?? ''}',
        platform: '${json['platform'] ?? ''}',
        arch: '${json['arch'] ?? ''}',
        root: '${json['root'] ?? ''}',
        python: '${json['python'] ?? ''}',
        installed: json['installed'] == true,
      );
    } catch (e) {
      status = ProxyStatus(error: '${pool.lastKeyError}$e'.trim());
    } finally {
      busy = '';
      await save();
      notifyListeners();
    }
    return status;
  }

  String _engineCommand(String rest) =>
      'CARBIDE_ROOT=$_rootExpr $_nodeExpr $_engineExpr $rest';

  /// 带插件配置地跑。配置是 JSON 文本，里面什么引号都可能有，
  /// 所以还是 base64 走管道，让 shell 只认得干净字符。
  String _engineCommandWith(String rest, String config) {
    final String own = config.trim();
    if (own.isEmpty) return _engineCommand(rest);
    // \$ 要转义：Dart 里 \$( 不是插值，直接写会报 missing_identifier。
    return _engineCommand('$rest --config "\$(printf %s ${_b64(own)} | base64 -d)"');
  }

  /// 把一份文本写到远端某个文件：`printf <base64> | base64 -d > 路径`。
  ///
  /// 比 SFTP 糙，但少一个子系统、少一个「目录在不在」的来回，
  /// 而桥脚本和调用参数都是几十 KB 的小东西，管道够用。
  /// 路径已经是 shell 表达式，这里原样接上去。
  String _putFile(String pathExpr, String text) =>
      'printf %s ${_b64(text)} | base64 -d > $pathExpr';

  /// call 那段参数。session 是对话 id，插件拿它找自己的会话日志；
  /// 空着就让引擎退回按工作目录算，至少不会串到别的插件头上。
  String _callRest(String id, String tool, String session) {
    final String tail = 'call ${_q(id)} ${_q(tool)} --args - --cwd $_workExpr';
    final String own = session.trim();
    if (own.isEmpty) return tail;
    return '$tail --session ${_q(own)}';
  }

  // ---------------------------------------------------------------- 装与删

  /// 装一个包，顺手收割一次清单。
  Future<PluginManifest> install(String package, {bool runScripts = false}) async {
    final HostEntry? host = proxyHost;
    if (host == null) throw StateError('还没选代理服务器。');
    final String pkg = package.trim();
    if (pkg.isEmpty) throw ArgumentError('要装哪个包？');
    await ensureReady();
    busy = '装 $pkg';
    notifyListeners();
    try {
      final String extra = runScripts ? ' --with-scripts' : '';
      final _Run ins = await _run(
        host,
        _engineCommand('install ${_q(pkg)}$extra'),
        timeout: const Duration(seconds: 300),
      );
      final Map<String, Object?> inJson = _lastJson(ins.out);
      if (inJson['ok'] != true) throw StateError(_explain(ins, '装不上 $pkg'));

      final _Run har = await _run(
        host,
        _engineCommand('harvest ${_q(pkg)}'),
        timeout: const Duration(seconds: 120),
      );
      final Map<String, Object?> json = _lastJson(har.out);
      if (json['ok'] != true) throw StateError(_explain(har, '$pkg 装上了但取不出工具'));

      final PluginManifest manifest = _manifestOf(json, pkg);
      _byId[pkg] = manifest;
      await save();
      // 新装的包可能带技能，顺手刷一下摘要
      await refreshSkills(fresh: true);
      return manifest;
    } finally {
      busy = '';
      notifyListeners();
    }
  }

  /// 重新收割一次清单（插件升级、或者手改了风险档之后）。
  Future<PluginManifest> refresh(String id) async {
    final HostEntry? host = proxyHost;
    if (host == null) throw StateError('还没选代理服务器。');
    final String cfg = _byId[id]?.config ?? '';
    final _Run har = await _run(
      host,
      _engineCommandWith('harvest ${_q(id)}', cfg),
      timeout: const Duration(seconds: 120),
    );
    final Map<String, Object?> json = _lastJson(har.out);
    if (json['ok'] != true) throw StateError(_explain(har, '取不出 $id 的工具'));
    final PluginManifest fresh = _manifestOf(json, id);
    final PluginManifest? old = _byId[id];
    _byId[id] = old == null
        ? fresh
        : fresh.copyWith(on: old.on, config: old.config, prompt: fresh.prompt);
    await save();
    notifyListeners();
    return _byId[id]!;
  }

  /// 从代理机上删掉这个包。
  Future<void> uninstall(String id) async {
    final HostEntry? host = proxyHost;
    if (host == null) throw StateError('还没选代理服务器。');
    busy = '删 $id';
    notifyListeners();
    try {
      await _run(host, _engineCommand('remove ${_q(id)}'), timeout: const Duration(seconds: 60));
      _byId.remove(id);
      await save();
    } finally {
      busy = '';
      notifyListeners();
      await refreshSkills(fresh: true);
    }
  }

  /// 技能库的一句话摘要，写进系统提示用。
  ///
  /// 为什么要缓存：系统提示是同步拼的，而技能在代理机上，
  /// 每轮都去问一遍太贵。装、卸、开关的时候刷一次就够。
  String skillsNote = '';

  DateTime _skillsAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 刷新技能摘要。代理机没准备好、或者命令失败，就留空——
  /// 技能库不存在不该让整个对话开不了。
  ///
  /// [fresh] 为 false 时一分钟内的旧结果直接用：切个对话就 SSH 一趟太浪费，
  /// 而技能列表又不会自己变。装、卸、开关是明确的变更点，那时候要 [fresh]。
  Future<void> refreshSkills({bool fresh = false}) async {
    final HostEntry? host = proxyHost;
    if (host == null) {
      skillsNote = '';
      return;
    }
    final DateTime now = DateTime.now();
    if (!fresh && now.difference(_skillsAt).inSeconds < 60) return;
    try {
      final _Run r = await _run(
        host,
        _engineCommand('skills --cwd $_workExpr'),
        timeout: const Duration(seconds: 30),
      );
      final Map<String, Object?> json = _lastJson(r.out);
      final Object? raw = json['skills'];
      if (raw is! List) {
        skillsNote = '';
        return;
      }
      final List<String> lines = <String>[];
      int hidden = 0;
      for (final Object? e in raw) {
        if (e is! Map) continue;
        final Map<String, Object?> m = Map<String, Object?>.from(e);
        if (m['modelInvocable'] != true) {
          hidden++;
          continue;
        }
        final String name = '${m['name'] ?? ''}'.trim();
        if (name.isEmpty) continue;
        final String desc = '${m['description'] ?? ''}'.trim();
        lines.add(desc.isEmpty ? '  $name' : '  $name = $desc');
      }
      if (lines.isEmpty) {
        skillsNote = '';
        return;
      }
      final StringBuffer b = StringBuffer();
      b.writeln('- 插件技能库（有对应的任务就先调 skill 工具按名字取全文，别猜）：');
      for (final String line in lines) {
        b.writeln(line);
      }
      if (hidden > 0) {
        b.writeln('  另有 $hidden 个技能不允许模型自己调用，不要尝试。');
      }
      skillsNote = b.toString();
    } catch (_) {
      skillsNote = '';
    } finally {
      _skillsAt = now;
    }
  }

  /// 代理机上有哪些包（包括没收割过的）。
  Future<List<String>> listRemote() async {
    final HostEntry? host = proxyHost;
    if (host == null) return const <String>[];
    final _Run r = await _run(host, _engineCommand('list'), timeout: const Duration(seconds: 60));
    final Map<String, Object?> json = _lastJson(r.out);
    final Object? raw = json['packages'];
    if (raw is! List) return const <String>[];
    return raw.map((Object? e) => '$e').toList(growable: false);
  }

  // ---------------------------------------------------------------- 调

  /// 调一个工具。参数 base64 之后走管道喂给桥的 stdin，省得跟引号打架。
  Future<PluginCallResult> call(
    String id,
    String tool,
    Map<String, Object?> args, {
    String session = '',
  }) async {
    final HostEntry? host = proxyHost;
    if (host == null) {
      return const PluginCallResult(ok: false, error: '还没选代理服务器。');
    }
    try {
      final String payload = _b64(jsonEncode(args));
      final String cfg = _byId[id]?.config ?? '';
      final _Run r = await _run(
        host,
        'printf %s $payload | base64 -d | ${_engineCommandWith(_callRest(id, tool, session), cfg)}',
        timeout: const Duration(seconds: 120),
      );
      final Map<String, Object?> json = _lastJson(r.out);
      if (json['ok'] != true) {
        return PluginCallResult(ok: false, error: _explain(r, '调用失败'));
      }
      final String text = '${json['text'] ?? ''}'.trim();
      final Object? result = json['result'];
      return PluginCallResult(
        ok: true,
        text: text.isNotEmpty ? text : _pretty(result),
        ms: json['ms'] is int ? json['ms'] as int : 0,
        raw: json,
      );
    } catch (e) {
      final String hint = pool.lastKeyError.isEmpty ? '' : pool.lastKeyError;
      return PluginCallResult(ok: false, error: '$hint$e'.trim());
    }
  }

  /// 部署过就直接用，没部署过先部署一次。
  Future<void> ensureReady() async {
    if (status.ok) return;
    await deploy();
    if (!status.ok) throw StateError(status.summary);
  }

  // ---------------------------------------------------------------- 底层

  Future<_Run> _run(HostEntry host, String command, {Duration timeout = const Duration(seconds: 60)}) async {
    final SSHClient client = await pool.connect(host);
    final SSHRunResult r = await client.runWithResult(command).timeout(timeout);
    return _Run(
      utf8.decode(r.stdout, allowMalformed: true),
      utf8.decode(r.stderr, allowMalformed: true),
      r.exitCode ?? 0,
    );
  }

  PluginManifest _manifestOf(Map<String, Object?> json, String pkg) {
    final List<PluginToolSpec> tools = <PluginToolSpec>[];
    final Object? raw = json['tools'];
    if (raw is List) {
      for (final Object? e in raw) {
        if (e is Map) tools.add(PluginToolSpec.fromJson(Map<String, Object?>.from(e)));
      }
    }
    // 插件写给模型的引导语：按 order 拼起来。这是它教模型「怎么用我的工具」
    // 的唯一渠道，丢了就等于让模型瞎猜。
    final StringBuffer prompt = StringBuffer();
    final Object? rawSections = json['sections'];
    if (rawSections is List) {
      for (final Object? e in rawSections) {
        if (e is! Map) continue;
        final String text = '${e['text'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        if (prompt.isNotEmpty) prompt.write('\n\n');
        prompt.write(text);
      }
    }
    return PluginManifest(
      id: pkg,
      version: '${json['version'] ?? ''}',
      pluginName: '${json['pluginName'] ?? ''}',
      tools: tools,
      inject: _list(json['inject']),
      warnings: _list(json['warnings']),
      missingSeams: _list(json['missingSeams']),
      node: '${json['node'] ?? ''}',
      installedAt: DateTime.now().toIso8601String(),
      config: _byId[pkg]?.config ?? '',
      prompt: prompt.toString(),
      on: _byId[pkg]?.on ?? true,
    );
  }

  List<String> _list(Object? raw) {
    if (raw is! List) return const <String>[];
    return raw.map((Object? e) => '$e').where((String s) => s.isNotEmpty).toList(growable: false);
  }

  /// 桥的输出是一行 JSON。万一前面混进了别的行，从后往前找第一行像样的。
  Map<String, Object?> _lastJson(String out) {
    final List<String> lines = out.split('\n').where((String l) => l.trim().startsWith('{')).toList();
    for (int i = lines.length - 1; i >= 0; i--) {
      try {
        final Object? decoded = jsonDecode(lines[i]);
        if (decoded is Map) return Map<String, Object?>.from(decoded);
      } catch (_) {
        continue;
      }
    }
    return <String, Object?>{};
  }

  String _explain(_Run r, String what) {
    final Map<String, Object?> json = _lastJson(r.out);
    final Object? own = json['error'];
    if (own != null && '$own'.trim().isNotEmpty) return '$what：$own';
    final String err = r.err.trim();
    if (err.isNotEmpty) return '$what：${_clip(err, 400)}';
    final String outText = r.out.trim();
    if (outText.isNotEmpty) return '$what：${_clip(outText, 400)}';
    return '$what（退出码 ${r.code}）';
  }

  String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

  String _pretty(Object? value) {
    if (value == null) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return '$value';
    }
  }
}

class _Run {
  const _Run(this.out, this.err, this.code);
  final String out;
  final String err;
  final int code;
}
