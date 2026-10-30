import 'package:carbide_shell/core/models.dart';
import 'package:carbide_shell/data/device.dart';
import 'package:carbide_shell/data/settings.dart';
import 'package:carbide_shell/data/tool_groups.dart';
import 'package:carbide_shell/tools/app_tools.dart';
import 'package:carbide_shell/tools/device_tools.dart';
import 'package:flutter_test/flutter_test.dart';

const ToolContext _ctx = ToolContext(workspace: '/tmp', desktop: true);

/// 假的手机：想让哪项权限开着就开着，做的事都记下来。
class FakeDevice implements DeviceApi {
  FakeDevice({
    this.supported = true,
    this.granted = const <DevicePerm>{},
    this.fix,
    this.book = const <DeviceContact>[],
    this.clip = '',
  });

  @override
  final bool supported;

  /// 已经允许的那几项。
  Set<DevicePerm> granted;

  DeviceFix? fix;
  List<DeviceContact> book;
  String clip;

  /// 要过权限的那几项，按顺序记着。
  final List<DevicePerm> asked = <DevicePerm>[];

  /// 真发出去的短信。
  final List<String> sent = <String>[];

  /// 分享出去的那几段。
  final List<String> shared = <String>[];

  /// 手机此刻的状态信号，默认是一台插着电、连着无线、亮着屏解好锁的手机。
  PhoneSignals signals = const PhoneSignals(
    battery: 85,
    charging: true,
    screenOn: true,
    locked: false,
    network: 'wifi',
    headset: false,
    ringer: 'normal',
    dnd: false,
    music: false,
  );

  @override
  Future<PhoneSignals> phoneState() async {
    if (!supported) throw const DeviceError('这台机器上没有手机那一套，只有安卓上才有。');
    return signals;
  }

  @override
  Future<DeviceInfo> info() async {
    if (!supported) throw const DeviceError('这台机器上没有手机那一套，只有安卓上才有。');
    return const DeviceInfo(
      brand: 'Xiaomi',
      model: '23113RKC6C',
      sdk: 36,
      abi: 'arm64-v8a',
      battery: 85,
      charging: true,
      network: 'wifi',
      freeMb: 12000,
      totalMb: 128000,
    );
  }

  @override
  Future<bool> has(DevicePerm perm) async => granted.contains(perm);

  @override
  Future<bool> request(DevicePerm perm) async {
    asked.add(perm);
    return granted.contains(perm);
  }

  @override
  Future<DeviceFix?> location() async => fix;

  @override
  Future<List<DeviceContact>> contacts({String query = '', int limit = 20}) async {
    final List<DeviceContact> hit = book
        .where((DeviceContact c) => query.isEmpty || c.name.contains(query))
        .take(limit)
        .toList();
    return hit;
  }

  @override
  Future<void> sendSms(String to, String text) async {
    sent.add('$to|$text');
  }

  @override
  Future<void> share(String text, {String subject = ''}) async {
    shared.add(text);
  }

  @override
  Future<String> clipboard() async => clip;

  @override
  Future<void> setClipboard(String text) async {
    clip = text;
  }

  /// 通知与使用时间的假数据，权限不给就抛。
  List<DeviceNotification> feed = <DeviceNotification>[];
  List<AppUsage> spent = <AppUsage>[];

  @override
  Future<List<DeviceNotification>> notifications({
    int limit = 40,
    int minutes = 720,
  }) async {
    if (!granted.contains(DevicePerm.notification)) {
      throw const DeviceError('没有通知读取权限');
    }
    return feed.take(limit).toList();
  }

  @override
  Future<List<AppUsage>> usage({int hours = 24}) async {
    if (!granted.contains(DevicePerm.usageAccess)) {
      throw const DeviceError('没有使用情况访问权限');
    }
    return spent;
  }

  @override
  Future<void> openNotificationAccess() async {}

  @override
  Future<void> openUsageAccess() async {}

  /// 打开过的应用、设过的闹钟与计时器、改过的音量。
  final List<String> opened = <String>[];
  final List<String> alarms = <String>[];
  final List<String> timers = <String>[];

  /// 名字 → 包名。
  Map<String, String> apps = <String, String>{'微信': 'com.tencent.mm'};

  DeviceVolume loud = const DeviceVolume(
    ok: true,
    music: 60,
    ring: 40,
    alarm: 80,
    notification: 30,
    mode: 'normal',
  );

  @override
  Future<OpenAppResult> openApp(String query) async {
    for (final MapEntry<String, String> e in apps.entries) {
      if (query == e.key || query == e.value) {
        opened.add(e.value);
        return OpenAppResult(ok: true, app: e.key, pkg: e.value);
      }
    }
    return const OpenAppResult(why: '这台手机上没找到这个应用', near: <String>['微信']);
  }

  @override
  Future<bool> setAlarm({
    required int hour,
    required int minute,
    String label = '',
    bool skipUi = true,
  }) async {
    alarms.add('${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}'
        '|$label|$skipUi');
    return true;
  }

  @override
  Future<bool> setTimer({required int seconds, String label = '', bool skipUi = true}) async {
    timers.add('$seconds|$label|$skipUi');
    return true;
  }

  @override
  Future<DeviceVolume> volume() async => loud;

  @override
  Future<DeviceVolume> setVolume({String stream = '', int percent = -1, String mode = ''}) async {
    loud = DeviceVolume(
      ok: true,
      music: stream == 'music' && percent >= 0 ? percent : loud.music,
      ring: stream == 'ring' && percent >= 0 ? percent : loud.ring,
      alarm: stream == 'alarm' && percent >= 0 ? percent : loud.alarm,
      notification: stream == 'notification' && percent >= 0 ? percent : loud.notification,
      mode: mode.isEmpty ? loud.mode : mode,
    );
    return loud;
  }
}

void main() {
  group('扩展清单', () {
    test('每一项的 id 与工具名都不重复，id 就是存进设置的那个字', () {
      final Set<String> ids = <String>{};
      final Set<String> names = <String>{};
      for (final ToolGroup g in kToolGroups) {
        expect(ids.add(g.id), isTrue, reason: 'id 重了：${g.id}');
        expect(g.name.isNotEmpty, isTrue);
        expect(g.tools.isNotEmpty, isTrue);
        for (final String t in g.tools) {
          expect(names.add(t), isTrue, reason: '工具重了：$t');
        }
      }
      expect(kToolGroups.length, 10);
      expect(toolGroupOf('notif')?.perm, DevicePerm.notification);
      expect(toolGroupOf('usage')?.perm, DevicePerm.usageAccess);
      expect(toolGroupOf('sms')?.perm, DevicePerm.sms);
      expect(toolGroupOf('device')?.perm, isNull);
      expect(toolGroupOf('没有这一项'), isNull);
    });

    test('开关存得进设置，也读得回来', () {
      final AppSettings s = AppSettings();
      expect(s.toolOn('device'), isFalse, reason: '默认一个都不开');
      s.setTool('device', true);
      s.setTool('sms', true);
      expect(s.toolOn('device'), isTrue);
      expect(s.enabledTools, <String>['device', 'sms']);

      final AppSettings again =
          AppSettings.fromJson(Map<String, Object?>.from(s.toJson()));
      expect(again.toolOn('device'), isTrue);
      expect(again.toolOn('sms'), isTrue);
      expect(again.toolOn('clipboard'), isFalse);

      again.setTool('device', false);
      expect(again.toolOn('device'), isFalse);
      expect(again.enabledTools, <String>['sms']);
    });
  });

  group('设备信息', () {
    test('把机型电量网络存储念出来', () async {
      final ToolOutcome out =
          await DeviceInfoTool(FakeDevice()).run(<String, Object?>{}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('23113RKC6C'));
      expect(out.stdout, contains('85%'));
      expect(out.stdout, contains('在充电'));
      expect(out.stdout, contains('无线'));
      expect(out.stdout, contains('12000'));
      expect(DeviceInfoTool(FakeDevice()).classify(<String, Object?>{}), ToolRisk.read);
    });

    test('桌面上如实说没有手机那一套', () async {
      final ToolOutcome out =
          await DeviceInfoTool(FakeDevice(supported: false)).run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('安卓'));
    });
  });

  group('剪贴板', () {
    test('读出来就是剪贴板里那段', () async {
      final FakeDevice phone = FakeDevice(clip: '一段字');
      final ToolOutcome out =
          await ClipboardTool(phone).run(<String, Object?>{'action': 'read'}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, '一段字');
    });

    test('空的时候说空，不编内容', () async {
      final ToolOutcome out = await ClipboardTool(FakeDevice())
          .run(<String, Object?>{'action': 'read'}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('没有文字'));
    });

    test('写进去要内容，而且算写操作', () async {
      final FakeDevice phone = FakeDevice();
      final ClipboardTool tool = ClipboardTool(phone);
      expect(tool.classify(<String, Object?>{'action': 'write'}), ToolRisk.write);
      expect(tool.classify(<String, Object?>{'action': 'read'}), ToolRisk.read);

      final ToolOutcome bad =
          await tool.run(<String, Object?>{'action': 'write'}, _ctx);
      expect(bad.ok, isFalse);

      final ToolOutcome out = await tool
          .run(<String, Object?>{'action': 'write', 'text': '交给模型的那句'}, _ctx);
      expect(out.ok, isTrue);
      expect(phone.clip, '交给模型的那句');
    });
  });

  group('定位', () {
    test('有定位就报经纬度、精度和时间', () async {
      final FakeDevice phone = FakeDevice(granted: <DevicePerm>{DevicePerm.location});
      phone.fix = DeviceFix(
        lat: 31.23041,
        lng: 121.47370,
        accuracy: 25,
        at: DateTime.now().subtract(const Duration(minutes: 3)),
      );
      final ToolOutcome out =
          await WhereAmITool(phone).run(<String, Object?>{}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('31.23041'));
      expect(out.stdout, contains('121.47370'));
      expect(out.stdout, contains('25 米'));
      expect(out.stdout, contains('3 分钟前'));
    });

    test('没权限就让人去设置里打开，不要坐标', () async {
      final ToolOutcome out =
          await WhereAmITool(FakeDevice()).run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('设置'));
    });

    test('系统里还没有定位就说还没有', () async {
      final ToolOutcome out = await WhereAmITool(
        FakeDevice(granted: <DevicePerm>{DevicePerm.location}),
      ).run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('还没有'));
    });
  });

  group('联系人', () {
    test('按名字找到号码', () async {
      final FakeDevice phone = FakeDevice(granted: <DevicePerm>{DevicePerm.contacts})
        ..book = const <DeviceContact>[
          DeviceContact(name: '张三', phone: '13800000000'),
          DeviceContact(name: '张四', phone: '13900000000'),
        ];
      final ToolOutcome out = await FindContactTool(phone)
          .run(<String, Object?>{'query': '张'}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('张三 13800000000'));
      expect(out.stdout, contains('张四 13900000000'));
    });

    test('没找到就说没有，不编一个人出来', () async {
      final ToolOutcome out = await FindContactTool(
        FakeDevice(granted: <DevicePerm>{DevicePerm.contacts}),
      ).run(<String, Object?>{'query': '李'}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('没有'));
    });

    test('没权限时先说没打开', () async {
      final ToolOutcome out =
          await FindContactTool(FakeDevice()).run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('联系人'));
    });
  });

  group('短信', () {
    test('有权限才发，内容原样过去', () async {
      final FakeDevice phone = FakeDevice(granted: <DevicePerm>{DevicePerm.sms});
      final ToolOutcome out = await SmsSendTool(phone).run(
          <String, Object?>{'to': '13800000000', 'text': '到家了'}, _ctx);
      expect(out.ok, isTrue);
      expect(phone.sent, <String>['13800000000|到家了']);
    });

    test('没权限时一条都不发', () async {
      final FakeDevice phone = FakeDevice();
      final ToolOutcome out = await SmsSendTool(phone)
          .run(<String, Object?>{'to': '13800000000', 'text': '到家了'}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('短信'));
      expect(phone.sent, isEmpty);
    });

    test('号码和内容都得有，号码还得像号码', () async {
      final FakeDevice phone = FakeDevice(granted: <DevicePerm>{DevicePerm.sms});
      final SmsSendTool tool = SmsSendTool(phone);
      expect((await tool.run(<String, Object?>{'text': '空号码'}, _ctx)).ok, isFalse);
      expect(
          (await tool.run(<String, Object?>{'to': '13800000000'}, _ctx)).ok, isFalse);
      expect(
          (await tool
                  .run(<String, Object?>{'to': '随便写的', 'text': '一句'}, _ctx))
              .ok,
          isFalse);
      expect(phone.sent, isEmpty);
      expect(tool.classify(<String, Object?>{}), ToolRisk.write);
    });

    test('审批卡上念得出发给谁、说了什么', () {
      final String line = SmsSendTool(FakeDevice())
          .summarize(<String, Object?>{'to': '13800000000', 'text': '到家了'});
      expect(line, contains('13800000000'));
      expect(line, contains('到家了'));
    });
  });

  group('分享', () {
    test('把那段话交给系统', () async {
      final FakeDevice phone = FakeDevice();
      final ToolOutcome out =
          await ShareTool(phone).run(<String, Object?>{'text': '这条要转出去'}, _ctx);
      expect(out.ok, isTrue);
      expect(phone.shared, <String>['这条要转出去']);
    });
  });

  group('通知与使用时间', () {
    test('没有通知读取权就如实说没有', () async {
      final ToolOutcome out =
          await NotifyReadTool(FakeDevice()).run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('权限'));
    });

    test('有权限就把时间、应用、标题正文排出来', () async {
      final FakeDevice phone = FakeDevice(granted: <DevicePerm>{DevicePerm.notification})
        ..feed = <DeviceNotification>[
          DeviceNotification(
            app: '微信',
            pkg: 'com.tencent.mm',
            title: '张三',
            text: '在吗',
            at: DateTime(2026, 10, 29, 9, 12),
          ),
        ];
      final ToolOutcome out =
          await NotifyReadTool(phone).run(<String, Object?>{'minutes': 60}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('微信'));
      expect(out.stdout, contains('张三：在吗'));
      expect(out.stdout, contains('09:12'));
    });

    test('按应用筛，筛不中就说没这条', () async {
      final FakeDevice phone = FakeDevice(granted: <DevicePerm>{DevicePerm.notification})
        ..feed = <DeviceNotification>[
          const DeviceNotification(app: '微信', pkg: 'com.tencent.mm', title: 'a', text: 'b'),
        ];
      final ToolOutcome out = await NotifyReadTool(phone)
          .run(<String, Object?>{'app': '支付宝'}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('没有'));
    });

    test('使用时间按时长排出来，末尾写合计', () async {
      final FakeDevice phone = FakeDevice(granted: <DevicePerm>{DevicePerm.usageAccess})
        ..spent = <AppUsage>[
          const AppUsage(app: '微信', pkg: 'mm', minutes: 95),
          const AppUsage(app: '终端', pkg: 'term', minutes: 20),
        ];
      final ToolOutcome out = await AppUsageTool(phone).run(<String, Object?>{}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('微信\t1 小时 35 分'));
      expect(out.stdout, contains('合计 1 小时 55 分'));
    });
  });

  group('应用、闹钟、音量', () {
    test('按名字打开应用', () async {
      final FakeDevice phone = FakeDevice();
      final ToolOutcome out =
          await OpenAppTool(phone).run(<String, Object?>{'query': '微信'}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('微信'));
      expect(phone.opened, <String>['com.tencent.mm']);
    });

    test('名字对不上就举几个像的，不瞎开一个', () async {
      final FakeDevice phone = FakeDevice();
      final ToolOutcome out =
          await OpenAppTool(phone).run(<String, Object?>{'query': '飞书'}, _ctx);
      expect(out.ok, isFalse);
      expect(out.error, contains('微信'));
      expect(phone.opened, isEmpty);
    });

    test('闹钟按时分写给系统，默认不出系统那一页', () async {
      final FakeDevice phone = FakeDevice();
      final ToolOutcome out = await SetAlarmTool(phone)
          .run(<String, Object?>{'hour': 6, 'minute': 5, 'label': '起来看看服务器'}, _ctx);
      expect(out.ok, isTrue);
      expect(phone.alarms, <String>['06:05|起来看看服务器|true']);
      expect(out.stdout, contains('06:05'));
    });

    test('闹钟没给小时就不设', () async {
      final FakeDevice phone = FakeDevice();
      final ToolOutcome out = await SetAlarmTool(phone).run(<String, Object?>{}, _ctx);
      expect(out.ok, isFalse);
      expect(phone.alarms, isEmpty);
    });

    test('计时器把分钟和秒加起来', () async {
      final FakeDevice phone = FakeDevice();
      final ToolOutcome out = await SetTimerTool(phone)
          .run(<String, Object?>{'minutes': 2, 'seconds': 30}, _ctx);
      expect(out.ok, isTrue);
      expect(phone.timers, <String>['150||true']);
      expect(out.stdout, contains('2 分 30 秒'));
    });

    test('不给参数就只看一眼，算读', () async {
      final FakeDevice phone = FakeDevice();
      final VolumeTool tool = VolumeTool(phone);
      expect(tool.classify(<String, Object?>{}), ToolRisk.read);
      final ToolOutcome out = await tool.run(<String, Object?>{}, _ctx);
      expect(out.ok, isTrue);
      expect(out.stdout, contains('音乐 60%'));
      expect(out.stdout, contains('铃声方式 正常'));
    });

    test('带参数就是改，算写', () async {
      final FakeDevice phone = FakeDevice();
      final VolumeTool tool = VolumeTool(phone);
      expect(tool.classify(<String, Object?>{'stream': 'music', 'percent': 10}), ToolRisk.write);
      final ToolOutcome out = await tool
          .run(<String, Object?>{'stream': 'music', 'percent': 10, 'mode': 'silent'}, _ctx);
      expect(out.ok, isTrue);
      expect(phone.loud.music, 10);
      expect(phone.loud.mode, 'silent');
      expect(out.stdout, contains('改好了'));
    });
  });
}
