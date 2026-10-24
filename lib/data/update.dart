import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../version.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.tag,
    required this.version,
    required this.pageUrl,
    required this.notes,
    required this.apkUrl,
    required this.publishedAt,
    required this.prerelease,
  });

  final String tag;
  final String version;
  final String pageUrl;
  final String notes;
  final String apkUrl;
  final String publishedAt;
  final bool prerelease;

  bool get newerThanCurrent => compareVersions(version, kAppVersion) > 0;
}

/// Reads the GitHub releases list and picks one. No token, so this is the
/// same 60-per-hour bucket every anonymous client shares.
class UpdateChecker {
  UpdateChecker({HttpClient? client}) : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 12);
  }

  final HttpClient _client;

  Future<List<UpdateInfo>> fetch({bool includePrerelease = false}) async {
    final HttpClientRequest req = await _client.getUrl(Uri.parse(kReleasesApi));
    req.headers.set('Accept', 'application/vnd.github+json');
    req.headers.set('User-Agent', 'CarbideShell/$kAppVersion');
    final HttpClientResponse res = await req.close();
    final String body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw HttpException('GitHub 返回 HTTP ${res.statusCode}');
    }
    final Object? decoded = jsonDecode(body);
    if (decoded is! List) throw const FormatException('返回的不是列表');
    final List<UpdateInfo> out = <UpdateInfo>[];
    for (final Object? raw in decoded) {
      if (raw is! Map) continue;
      final UpdateInfo? info = parseRelease(Map<String, Object?>.from(raw));
      if (info == null) continue;
      if (info.prerelease && !includePrerelease) continue;
      out.add(info);
    }
    return out;
  }

  void close() => _client.close(force: true);
}

UpdateInfo? parseRelease(Map<String, Object?> json) {
  final String tag = '${json['tag_name'] ?? ''}';
  if (tag.isEmpty) return null;
  String apk = '';
  final Object? assets = json['assets'];
  if (assets is List) {
    // 装包按架构分开出，手机几乎都是 arm64，拿不到就退到第一个 apk。
    final Map<String, String> byAbi = <String, String>{};
    String first = '';
    for (final Object? a in assets) {
      if (a is! Map) continue;
      final String name = '${a['name'] ?? ''}';
      if (!name.endsWith('.apk')) continue;
      final String url = '${a['browser_download_url'] ?? ''}';
      if (first.isEmpty) first = url;
      for (final String abi in kApkAbis) {
        if (name.contains(abi)) byAbi[abi] = url;
      }
    }
    for (final String abi in kApkAbis) {
      final String? url = byAbi[abi];
      if (url != null) {
        apk = url;
        break;
      }
    }
    if (apk.isEmpty) apk = first;
  }
  return UpdateInfo(
    tag: tag,
    version: normaliseVersion(tag),
    pageUrl: '${json['html_url'] ?? kProjectUrl}/releases',
    notes: '${json['body'] ?? ''}',
    apkUrl: apk,
    publishedAt: '${json['published_at'] ?? ''}',
    prerelease: json['prerelease'] == true || json['draft'] == true,
  );
}

/// 装包按架构分开出，优先挑 arm64 那一个。
const List<String> kApkAbis = <String>['arm64-v8a', 'armeabi-v7a', 'x86_64'];

String normaliseVersion(String tag) {
  String v = tag.trim();
  if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
  final int dash = v.indexOf('-');
  if (dash > 0) v = v.substring(0, dash);
  final int plus = v.indexOf('+');
  if (plus > 0) v = v.substring(0, plus);
  return v;
}

/// Returns >0 when [a] is newer than [b]. Missing parts count as zero.
int compareVersions(String a, String b) {
  final List<int> pa = _parts(a);
  final List<int> pb = _parts(b);
  final int n = pa.length > pb.length ? pa.length : pb.length;
  for (int i = 0; i < n; i += 1) {
    final int va = i < pa.length ? pa[i] : 0;
    final int vb = i < pb.length ? pb[i] : 0;
    if (va != vb) return va - vb;
  }
  return 0;
}

List<int> _parts(String v) => normaliseVersion(v)
    .split('.')
    .map((String p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
    .toList();

/// The first few meaningful lines of a release body, for a dialog.
String shortNotes(String body, {int max = 6}) {
  final List<String> lines = body
      .split('\n')
      .map((String l) => l.trim())
      .where((String l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
  if (lines.isEmpty) return '这个版本没有写说明。';
  return lines.take(max).join('\n');
}
