import 'core/agent.dart';
import 'core/memory.dart';
import 'core/policy.dart';
import 'data/hosts.dart';
import 'data/secrets.dart';
import 'data/settings.dart';
import 'tools/ssh_tools.dart';

/// Everything the UI needs, built once at startup.
class AppServices {
  AppServices({
    required this.hosts,
    required this.secrets,
    required this.settings,
    required this.policy,
    required this.agent,
    required this.pool,
    required this.memory,
  });

  final HostStore hosts;
  final SecretStore secrets;
  final SettingsStore settings;
  final ApprovalPolicy policy;
  final AgentLoop agent;
  final SshPool pool;
  final MemoryStore memory;
}
