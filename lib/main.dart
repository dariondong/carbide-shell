import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/conversation.dart';
import 'core/models.dart';
import 'core/memory.dart';
import 'core/policy.dart';
import 'data/activity.dart';
import 'data/hosts.dart';
import 'data/hub.dart';
import 'data/llm_settings.dart';
import 'data/mail.dart';
import 'data/secrets.dart';
import 'data/settings.dart';
import 'data/tasks.dart';
import 'data/temp_files.dart';
import 'data/usage.dart';
import 'data/watch.dart';
import 'services.dart';
import 'tools/ssh_tools.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 铺到屏幕边上：两条系统栏都用透明底，纸面自己透上去。
  // 三键导航（金刚键）会压掉底下那一截，所以底部由 SafeArea 让出距离。
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: Color(0x00000000),
    systemNavigationBarDividerColor: Color(0x00000000),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  final Directory dir = await getApplicationSupportDirectory();
  final Directory workspace = Directory('${dir.path}/workspace')..createSync(recursive: true);

  final HostStore hosts = HostStore(File('${dir.path}/hosts.json'));
  await hosts.load();
  final SettingsStore settings = SettingsStore(File('${dir.path}/settings.json'));
  await settings.load();

  final MemoryBook memory = MemoryBook(Directory('${dir.path}/memory'));
  final ConversationStore conversations = ConversationStore(Directory('${dir.path}/conversations'));
  await conversations.load();

  const SecretStore secrets = SecureSecretStore();
  final SshPool pool = SshPool(hosts: hosts, secrets: secrets);

  final TaskStore tasks = TaskStore(File('${dir.path}/tasks.json'));
  await tasks.load();
  final WatchStore watches = WatchStore(File('${dir.path}/watches.json'));
  await watches.load();
  final UsageStore usage = UsageStore(File('${dir.path}/usage.json'));
  await usage.load();
  final MailStore mail = MailStore(File('${dir.path}/mail.json'), secrets);
  await mail.load();

  // 一条通知、一个托管处：几个对话和定时任务同时跑也只有一个地方在写。
  final ActivityBoard board = ActivityBoard(styleOf: () => settings.value.notifStyle);

  final AppServices services = AppServices(
    hosts: hosts,
    secrets: secrets,
    settings: settings,
    policy: ApprovalPolicy(mode: _modeFrom(settings.value.approvalMode)),
    pool: pool,
    memory: memory,
    conversations: conversations,
    tasks: tasks,
    watches: watches,
    usage: usage,
    mail: mail,
    workspace: workspace.path,
    files: TempFiles(workspace),
  );

  runApp(CarbideApp(
    services: services,
    hub: SessionHub(services: services, board: board),
    scheduler: TaskScheduler(
      services: services,
      tasks: tasks,
      watches: watches,
      board: board,
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
