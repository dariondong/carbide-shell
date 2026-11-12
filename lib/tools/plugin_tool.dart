import 'dart:convert';

import '../core/models.dart';
import '../core/plugin.dart';
import '../core/tools.dart';
import '../data/plugins.dart';

/// 把一个远程插件工具接进本地清单。
///
/// 模型看到的是原样的名字和原样的 JSON Schema——跟插件作者写的一模一样，
/// 不用改写、不用翻译。真跑的时候参数原封不动发到代理机上。
class PluginTool extends Tool {
  PluginTool({
    required this.plugins,
    required this.pluginId,
    required this.spec,
    this.guidance = '',
  });

  final PluginStore plugins;
  final String pluginId;
  final PluginToolSpec spec;

  /// 插件作者写给模型的引导语。dsh 里它走 systemPrompt，这边没有独立通道，
  /// 并进工具描述——总比丢掉强，模型至少知道该怎么用它。
  final String guidance;

  @override
  String get name => spec.name;

  @override
  String get description {
    final String own = spec.description.trim();
    final String base = own.isNotEmpty ? own : '来自插件 $pluginId 的工具。';
    final String guide = guidance.trim();
    if (guide.isEmpty) return base;
    // 引导语是别人写的，长度不可控，这里截一刀防止把上下文撑爆。
    final String clipped = guide.length <= 2000 ? guide : '${guide.substring(0, 2000)}…';
    return '$base\n\n$clipped';
  }

  @override
  Map<String, Object?> get schema => spec.schema;

  @override
  ToolRisk get risk => spec.isRead ? ToolRisk.read : ToolRisk.write;

  @override
  String summarize(Map<String, Object?> args) {
    if (args.isEmpty) return spec.name;
    final String compact = jsonEncode(args);
    final String clipped = compact.length <= 120 ? compact : '${compact.substring(0, 120)}…';
    return '$pluginId · $clipped';
  }

  @override
  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context) async {
    final PluginCallResult r = await plugins.call(pluginId, spec.name, args);
    if (!r.ok) {
      return ToolOutcome.failure('插件 $pluginId 的 ${spec.name} 没跑成：${r.error}');
    }
    return ToolOutcome.success(
      stdout: r.text.isEmpty ? '（工具跑完了，但没有可读的输出）' : r.text,
      meta: <String, Object?>{
        'plugin': pluginId,
        'tool': spec.name,
        'ms': r.ms,
      },
    );
  }
}

/// 插件工具的挂载表。
///
/// 每个对话有自己的一张工具清单，所以这里不留状态——[sync] 每次都照着
/// 现在的插件表从头对齐一遍：不该挂的摘掉，该挂的挂上，名字撞了就让着本地的。
class PluginToolSet {
  PluginToolSet({required this.plugins, required this.registry});

  final PluginStore plugins;
  final ToolRegistry registry;

  /// 上一轮对齐时撞名的，界面上能看到，不至于默默失效。
  final List<String> conflicts = <String>[];

  void sync() {
    conflicts.clear();

    final Map<String, PluginManifest> want = <String, PluginManifest>{};
    for (final PluginManifest m in plugins.plugins) {
      if (!m.on) continue;
      for (final PluginToolSpec s in m.tools) {
        if (s.name.trim().isNotEmpty) want[s.name] = m;
      }
    }

    // 先摘：以前挂着、现在关了或者删了的插件工具。
    for (final String name in registry.names) {
      final Tool? t = registry.byName(name);
      if (t is PluginTool && !want.containsKey(name)) registry.unregister(name);
    }

    // 再挂。本地工具优先，插件想盖掉 read / ssh_exec 这种名字是不行的。
    for (final MapEntry<String, PluginManifest> e in want.entries) {
      final Tool? existing = registry.byName(e.key);
      if (existing != null && existing is! PluginTool) {
        conflicts.add('${e.value.id} 的 ${e.key} 跟本地工具重名，没挂上');
        continue;
      }
      registry.register(PluginTool(
        plugins: plugins,
        pluginId: e.value.id,
        spec: e.value.tools.firstWhere((PluginToolSpec s) => s.name == e.key),
        guidance: e.value.prompt,
      ));
    }
  }
}
