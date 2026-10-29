import 'device.dart';

/// 一项扩展：一组手机上的工具，用户自己决定开不开。
///
/// 关着的那组不进模型的工具清单，模型也就不会去试。
class ToolGroup {
  const ToolGroup({
    required this.id,
    required this.name,
    required this.note,
    required this.tools,
    this.perm,
  });

  /// 存进设置里的那个字符串，别改。
  final String id;

  /// 设置界面上写的名字。
  final String name;

  /// 一句话说这项能做什么。
  final String note;

  /// 这一组里的工具名，设置页照着列出来。
  final List<String> tools;

  /// 打开这一项时要向系统申请的权限。不要权限的是 null。
  final DevicePerm? perm;
}

const List<ToolGroup> kToolGroups = <ToolGroup>[
  ToolGroup(
    id: 'device',
    name: '设备信息',
    note: '机型、电量、网络、剩余存储',
    tools: <String>['device_info'],
  ),
  ToolGroup(
    id: 'clipboard',
    name: '剪贴板',
    note: '读一段、写一段',
    tools: <String>['clipboard'],
  ),
  ToolGroup(
    id: 'launch',
    name: '打开与分享',
    note: '用浏览器打开网址，或者交给系统的分享面板',
    tools: <String>['open_url', 'share_text'],
  ),
  ToolGroup(
    id: 'location',
    name: '定位',
    note: '最近一次定位的经纬度和精度',
    tools: <String>['where_am_i'],
    perm: DevicePerm.location,
  ),
  ToolGroup(
    id: 'contacts',
    name: '联系人',
    note: '按名字在通讯录里找号码',
    tools: <String>['find_contact'],
    perm: DevicePerm.contacts,
  ),
  ToolGroup(
    id: 'sms',
    name: '短信',
    note: '给一个号码发一条短信',
    tools: <String>['sms_send'],
    perm: DevicePerm.sms,
  ),
  ToolGroup(
    id: 'notif',
    name: '通知',
    note: '最近收到的通知：哪个应用、标题、正文',
    tools: <String>['notifications'],
    perm: DevicePerm.notification,
  ),
  ToolGroup(
    id: 'usage',
    name: '使用时间',
    note: '每个应用最近用了多久',
    tools: <String>['app_usage'],
    perm: DevicePerm.usageAccess,
  ),
];

/// 按 id 找那一项。找不到就是 null。
ToolGroup? toolGroupOf(String id) {
  for (final ToolGroup g in kToolGroups) {
    if (g.id == id) return g;
  }
  return null;
}
