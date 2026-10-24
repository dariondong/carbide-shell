import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/agent.dart';
import 'core/journal.dart';
import 'core/models.dart';
import 'core/policy.dart';
import 'core/tools.dart';
import 'data/hosts.dart';
import 'data/llm_settings.dart';
import 'data/secrets.dart';
import 'data/settings.dart';
import 'services.dart';
import 'tools/http_tool.dart';
import 'tools/local_tools.dart';
import 'tools/ssh_tools.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final Directory dir = await getApplicationSupportDirectory();
  final Directory workspace = Directory('${dir.path}/workspace')..createSync(recursive: true);

  final HostStore hosts = HostStore(File('${dir.path}/hosts.json'));
  await hosts.load();
  final SettingsStore settings = SettingsStore(File('${dir.path}/settings.json'));
  await settings.load();

  const SecretStore secrets = SecureSecretStore();
  final SshPool pool = SshPool(hosts: hosts, secrets: secrets);

  final ToolRegistry registry = ToolRegistry()
    ..register(SshExecTool(pool, hosts))
    ..register(SshSftpTool(pool, hosts))
    ..register(HttpTool(settings))
    ..register(FileTool())
    ..register(RememberTool());
  if (isDesktopPlatform) {
    registry.register(LocalExecTool());
  }

  final ApprovalPolicy policy = ApprovalPolicy(mode: _modeFrom(settings.value.approvalMode));
  final AgentLoop agent = AgentLoop(
    llm: SettingsLlmProvider(settings, secrets),
    registry: registry,
    policy: policy,
    journal: FileJournal(File('${dir.path}/journal.jsonl')),
    context: ToolContext(workspace: workspace.path, desktop: isDesktopPlatform),
    maxSteps: settings.value.maxSteps,
  );

  runApp(CarbideApp(
    services: AppServices(
      hosts: hosts,
      secrets: secrets,
      settings: settings,
      policy: policy,
      agent: agent,
      pool: pool,
    ),
  ));
}

ApprovalMode _modeFrom(String name) {
  switch (name) {
    case 'autoAll':
      return ApprovalMode.autoAll;
    case 'askAll':
      return ApprovalMode.askAll;
    default:
      return ApprovalMode.autoRead;
  }
}
