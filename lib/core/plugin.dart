/// 一个远程插件的清单。
///
/// 手机自己不跑插件代码，只认这份清单：清单上说有这个工具、参数长什么样，
/// 模型就照着调；真跑的时候发到代理机上去。
class PluginToolSpec {
  const PluginToolSpec({
    required this.name,
    required this.description,
    required this.schema,
    this.risk = 'write',
    this.renders = false,
  });

  final String name;
  final String description;

  /// 插件作者写的 JSON Schema，原样交给模型。
  final Map<String, Object?> schema;

  /// 'read' 或 'write'。插件本身没有这个概念，是从工具名推的，用户能改。
  final String risk;

  /// 工具有没有自带渲染函数。有的话代理机会顺手把结果排成给人看的样子。
  final bool renders;

  bool get isRead => risk == 'read';

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'description': description,
        'schema': schema,
        'risk': risk,
        if (renders) 'renders': true,
      };

  static PluginToolSpec fromJson(Map<String, Object?> json) {
    final Object? raw = json['schema'];
    return PluginToolSpec(
      name: '${json['name'] ?? ''}',
      description: '${json['description'] ?? ''}',
      schema: raw is Map ? Map<String, Object?>.from(raw) : <String, Object?>{'type': 'object'},
      risk: '${json['risk'] ?? 'write'}',
      renders: json['renders'] == true,
    );
  }

  PluginToolSpec copyWith({String? risk}) => PluginToolSpec(
        name: name,
        description: description,
        schema: schema,
        risk: risk ?? this.risk,
        renders: renders,
      );
}

/// 装好并收割过的一个插件。
class PluginManifest {
  const PluginManifest({
    required this.id,
    required this.version,
    required this.pluginName,
    required this.tools,
    this.inject = const <String>[],
    this.warnings = const <String>[],
    this.missingSeams = const <String>[],
    this.node = '',
    this.installedAt = '',
    this.config = '',
    this.prompt = '',
    this.on = true,
  });

  /// npm 包名，也是这张表里的主键。
  final String id;

  final String version;

  /// 插件自己起的名字（cordis 的 `name`）。
  final String pluginName;

  final List<PluginToolSpec> tools;

  /// 插件 inject 声明的服务。
  final List<String> inject;

  /// 装配时它往系统提示词里塞了几段（这里只记名字，不占上下文）。
  final List<String> warnings;

  /// 代理机上没提供的服务。空表示这个插件吃得很顺。
  final List<String> missingSeams;

  final String node;
  final String installedAt;

  /// 插件自己要求的配置（JSON 文本）。空表示它不需要配置。
  /// 有些插件在装配阶段就校验配置，缺了连工具清单都出不来。
  final String config;

  /// 插件写给模型的引导语，按 order 拼好了。
  /// 以前这一段被整个丢掉，模型只看到工具名和一个 schema。
  final String prompt;

  /// 装着但可以临时关掉：关掉只是不挂到模型清单上，包还在。
  final bool on;

  String get label {
    final String own = pluginName.trim();
    if (own.isEmpty || own == 'unknown') return id;
    return own;
  }

  /// 清单上那句现状。
  String get note {
    final String ver = version.isEmpty ? '' : ' $version';
    return '$id$ver · ${tools.length} 个工具';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'version': version,
        'pluginName': pluginName,
        'tools': tools.map((PluginToolSpec t) => t.toJson()).toList(),
        if (inject.isNotEmpty) 'inject': inject,
        if (warnings.isNotEmpty) 'warnings': warnings,
        if (missingSeams.isNotEmpty) 'missingSeams': missingSeams,
        if (node.isNotEmpty) 'node': node,
        if (installedAt.isNotEmpty) 'installedAt': installedAt,
        if (config.isNotEmpty) 'config': config,
        if (prompt.isNotEmpty) 'prompt': prompt,
        'on': on,
      };

  static PluginManifest fromJson(Map<String, Object?> json) {
    final List<PluginToolSpec> tools = <PluginToolSpec>[];
    final Object? rawTools = json['tools'];
    if (rawTools is List) {
      for (final Object? t in rawTools) {
        if (t is Map) tools.add(PluginToolSpec.fromJson(Map<String, Object?>.from(t)));
      }
    }
    return PluginManifest(
      id: '${json['id'] ?? ''}',
      version: '${json['version'] ?? ''}',
      pluginName: '${json['pluginName'] ?? ''}',
      tools: tools,
      inject: _strings(json['inject']),
      warnings: _strings(json['warnings']),
      missingSeams: _strings(json['missingSeams']),
      node: '${json['node'] ?? ''}',
      installedAt: '${json['installedAt'] ?? ''}',
      config: '${json['config'] ?? ''}',
      prompt: '${json['prompt'] ?? ''}',
      on: json['on'] != false,
    );
  }

  PluginManifest copyWith({
    bool? on,
    List<PluginToolSpec>? tools,
    String? config,
    String? prompt,
  }) =>
      PluginManifest(
        id: id,
        version: version,
        pluginName: pluginName,
        tools: tools ?? this.tools,
        inject: inject,
        warnings: warnings,
        missingSeams: missingSeams,
        node: node,
        installedAt: installedAt,
        config: config ?? this.config,
        prompt: prompt ?? this.prompt,
        on: on ?? this.on,
      );
}

List<String> _strings(Object? raw) {
  if (raw is! List) return const <String>[];
  return raw.map((Object? e) => '$e').where((String s) => s.isNotEmpty).toList(growable: false);
}

/// 代理机体检的结果。
class ProxyStatus {
  const ProxyStatus({
    this.ok = false,
    this.error = '',
    this.node = '',
    this.platform = '',
    this.arch = '',
    this.root = '',
    this.python = '',
    this.installed = false,
  });

  final bool ok;
  final String error;
  final String node;
  final String platform;
  final String arch;
  final String root;
  final String python;
  final bool installed;

  String get summary {
    if (!ok) return error.isEmpty ? '还没部署' : error;
    final String py = python.isEmpty ? '无 python' : python;
    return '$node · $arch · $py';
  }
}

/// 一次远程工具调用的结果。
class PluginCallResult {
  const PluginCallResult({
    required this.ok,
    this.text = '',
    this.error = '',
    this.ms = 0,
    this.raw = const <String, Object?>{},
  });

  final bool ok;
  final String text;
  final String error;
  final int ms;
  final Map<String, Object?> raw;
}
