/// 手机此刻的状态信号：充电、电量、网络、亮屏、锁屏、耳机、铃音、勿扰、在放音乐。
///
/// 这一层是纯 Dart：只有数据与写法，怎么从系统读出来在 data/device.dart 里。
library;

/// 手机此刻的状态信号。拿不到的项就不在表里，没编的默认值。
class PhoneSignals {
  const PhoneSignals({
    this.battery = -1,
    this.charging = false,
    this.screenOn,
    this.locked,
    this.network = '',
    this.headset,
    this.ringer = '',
    this.dnd,
    this.music,
  });

  factory PhoneSignals.fromMap(Map<Object?, Object?> m) {
    bool? flag(String key) => m.containsKey(key) ? m[key] == true : null;
    return PhoneSignals(
      battery: (m['battery'] as num?)?.toInt() ?? -1,
      charging: m['charging'] == true,
      screenOn: flag('screenOn'),
      locked: flag('locked'),
      network: '${m['network'] ?? ''}',
      headset: flag('headset'),
      ringer: '${m['ringer'] ?? ''}',
      dnd: flag('dnd'),
      music: flag('music'),
    );
  }

  final int battery;
  final bool charging;
  final bool? screenOn;
  final bool? locked;
  final String network;
  final bool? headset;

  /// `silent` / `vibrate` / `normal`
  final String ringer;
  final bool? dnd;
  final bool? music;

  /// 这次拿到手的项。用户只能在这些范围里让 AI 看。
  List<String> get present => <String>[
        if (battery >= 0) 'battery',
        if (charging) 'charging',
        if (screenOn != null) 'screenOn',
        if (locked != null) 'locked',
        if (network.isNotEmpty) 'network',
        if (headset != null) 'headset',
        if (ringer.isNotEmpty) 'ringer',
        if (dnd != null) 'dnd',
        if (music != null) 'music',
      ];

  /// 一行一件事，给模型看。
  String render() {
    final List<String> lines = <String>[
      if (battery >= 0) '电量：$battery%${charging ? '，在充电' : ''}',
      if (screenOn != null) '屏幕：${screenOn! ? '亮着' : '黑着'}',
      if (locked != null) '锁屏：${locked! ? '锁着' : '已解锁'}',
      if (network.isNotEmpty) '网络：${networkName(network)}',
      if (headset != null) '耳机：${headset! ? '连着' : '没连'}',
      if (ringer.isNotEmpty)
        '铃音：${switch (ringer) {
          'silent' => '静音',
          'vibrate' => '振动',
          _ => '响铃',
        }}',
      if (dnd != null) '勿扰：${dnd! ? '开着' : '没开'}',
      if (music != null) '在放音乐：${music! ? '是' : '不是'}',
    ];
    return lines.isEmpty ? '这台机器没给出任何状态信号。' : lines.join('\n');
  }
}

/// 网络类型写成人话。
String networkName(String code) => switch (code) {
      'wifi' => '无线',
      'mobile' => '移动数据',
      'ethernet' => '网线',
      'vpn' => '连着 VPN',
      'offline' => '没联网',
      _ => code,
    };
