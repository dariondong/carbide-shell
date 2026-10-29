import 'models.dart';

/// A capability the model may ask for.
abstract class Tool {
  String get name;

  String get description;

  /// JSON Schema for the arguments.
  Map<String, Object?> get schema;

  ToolRisk get risk => ToolRisk.write;

  /// The risk of one concrete call. `ssh_exec` looks at the command here.
  ToolRisk classify(Map<String, Object?> args) => risk;

  /// 不论审批档位都先问一句。改参数、写密钥、发邮件这类「说好才做」的事用它。
  bool get alwaysAsk => false;

  /// One line shown on the approval card. Empty when the tool has nothing to say.
  String summarize(Map<String, Object?> args) => '';

  Future<ToolOutcome> run(Map<String, Object?> args, ToolContext context);
}

class ToolRegistry {
  final Map<String, Tool> _byName = <String, Tool>{};

  void register(Tool tool) {
    _byName[tool.name] = tool;
  }

  void registerAll(Iterable<Tool> tools) {
    for (final Tool t in tools) {
      register(t);
    }
  }

  Tool? byName(String name) => _byName[name];

  /// 把一件工具从清单里拿下来。扩展关掉时用得上。
  void unregister(String name) {
    _byName.remove(name);
  }

  bool contains(String name) => _byName.containsKey(name);

  List<String> get names => _byName.keys.toList(growable: false);

  List<ToolSpec> specs() {
    final List<ToolSpec> out = <ToolSpec>[];
    for (final Tool t in _byName.values) {
      out.add(ToolSpec(name: t.name, description: t.description, schema: t.schema));
    }
    return out;
  }
}
