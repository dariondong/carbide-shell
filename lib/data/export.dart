import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// Android 那边写下载目录的通道；别的平台没有这条通道。
const MethodChannel _files = MethodChannel('top.theez.carbide_shell/files');

/// 常见后缀对应的类型。写进 MediaStore 只是为了相册、阅读器认得。
const Map<String, String> _mime = <String, String>{
  'txt': 'text/plain',
  'md': 'text/markdown',
  'markdown': 'text/markdown',
  'html': 'text/html',
  'htm': 'text/html',
  'json': 'application/json',
  'csv': 'text/csv',
  'xml': 'application/xml',
  'pdf': 'application/pdf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'zip': 'application/zip',
  'gz': 'application/gzip',
  'tar': 'application/x-tar',
  'apk': 'application/vnd.android.package-archive',
};

String mimeOf(String name) {
  final int dot = name.lastIndexOf('.');
  if (dot < 0 || dot == name.length - 1) return 'application/octet-stream';
  return _mime[name.substring(dot + 1).toLowerCase()] ?? 'application/octet-stream';
}

/// 存一份到系统的下载目录，回一句话说存哪儿了。
///
/// Android 直接写进「下载」（不需要存储权限）；桌面与网页退回系统的保存框，
/// 存到哪里由那一下选择决定。
Future<String> saveToDownloads({
  required String name,
  required Uint8List bytes,
}) async {
  try {
    final String? where = await _files.invokeMethod<String>('save', <String, Object?>{
      'name': name,
      'bytes': bytes,
      'mime': mimeOf(name),
    });
    if (where != null && where.isNotEmpty) return where;
  } on MissingPluginException {
    // 桌面、网页没有这条通道，走下面那条。
  } on PlatformException catch (e) {
    throw Exception(e.message ?? e.code);
  }
  final String? picked = await FilePicker.platform.saveFile(
    dialogTitle: '存到哪儿',
    fileName: name,
    bytes: bytes,
  );
  if (picked == null || picked.isEmpty) throw Exception('没有选保存位置。');
  return picked;
}
