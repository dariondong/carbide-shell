import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/html.dart';
import '../core/output_refs.dart';
import '../data/export.dart';
import '../data/temp_files.dart';
import 'components.dart';
import 'md_text.dart';
import 'motion.dart';
import 'theme.dart';

/// 一句话里提到、临时区里确实有的那几个文件。不在的一律不显示。
List<String> localOutputs(TempFiles files, String text) {
  final List<String> out = <String>[];
  for (final String ref in outputRefs(text)) {
    final String rel = files.relativize(ref);
    final File? f = files.fileOf(rel);
    if (f != null && f.existsSync()) out.add(rel);
  }
  return out;
}

/// 模型写出来的图和网页，在对话里直接看：图是一张小样，网页先收成文字再画。
class OutputPreview extends StatelessWidget {
  const OutputPreview({super.key, required this.files, required this.paths});

  final TempFiles files;
  final List<String> paths;

  @override
  Widget build(BuildContext context) {
    if (paths.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final String path in paths) _tile(context, path),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, String path) {
    final File? file = files.fileOf(path);
    if (file == null || !file.existsSync()) return const SizedBox.shrink();
    final String name = path.split('/').last;
    if (isImageRef(path)) {
      return GestureDetector(
        onTap: () => _openImage(context, file, name),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(C.radiusSmall),
          child: Container(
            width: 116,
            height: 92,
            decoration: BoxDecoration(
              color: C.paper2,
              border: Border.all(color: C.rule2),
              borderRadius: BorderRadius.circular(C.radiusSmall),
            ),
            child: Image.file(
              file,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (BuildContext ctx, Object error, StackTrace? stack) => Center(
                child: Text('读不出这张图',
                    style: C.monoSmall.copyWith(color: C.grey2, fontSize: 10.5)),
              ),
            ),
          ),
        ),
      );
    }
    final int bytes = file.existsSync() ? file.lengthSync() : 0;
    return GestureDetector(
      onTap: () => _openHtml(context, file, name),
      child: Container(
        width: 168,
        height: 92,
        padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: C.rule),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.language, size: 13, color: C.blue),
                const SizedBox(width: 6),
                const Text('网页',
                    style: TextStyle(fontSize: 10, color: C.blue, height: 1.3)),
                const Spacer(),
                Text(tempSize(bytes),
                    style: C.monoSmall.copyWith(fontSize: 9.5, color: C.grey2)),
              ],
            ),
            const SizedBox(height: 7),
            Expanded(
              child: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: C.mono.copyWith(fontSize: 11.5, color: C.ink, height: 1.4),
              ),
            ),
            Text('点开看看', style: C.monoSmall.copyWith(fontSize: 9.5, color: C.grey2)),
          ],
        ),
      ),
    );
  }

  void _openImage(BuildContext context, File file, String name) {
    final Uint8List? bytes = _read(file);
    if (bytes == null) return;
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: const Color(0xF2181C23),
      transitionDuration: Motion.swap,
      pageBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b) =>
          _ImageViewer(bytes: bytes, name: name),
      transitionsBuilder:
          (BuildContext ctx, Animation<double> a, Animation<double> b, Widget child) =>
              FadeTransition(opacity: a, child: child),
    ));
  }

  void _openHtml(BuildContext context, File file, String name) {
    String body;
    try {
      body = file.readAsStringSync();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('读不出来：$e')));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => _HtmlSheet(name: name, html: body, file: file),
    );
  }

  Uint8List? _read(File file) {
    try {
      return file.readAsBytesSync();
    } catch (_) {
      return null;
    }
  }
}

/// 全屏看一张：双指能放大，点一下退出。
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.bytes, required this.name});

  final Uint8List bytes;
  final String name;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: Scaffold(
        backgroundColor: const Color(0x00000000),
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 6,
                child: Center(
                  child: Text(name,
                      style: const TextStyle(
                          fontSize: 12, color: C.onInk, letterSpacing: 0.3)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 网页输出：一份收成文字画出来，一份原文，另加一个存到手机的键。
class _HtmlSheet extends StatefulWidget {
  const _HtmlSheet({required this.name, required this.html, required this.file});

  final String name;
  final String html;
  final File file;

  @override
  State<_HtmlSheet> createState() => _HtmlSheetState();
}

class _HtmlSheetState extends State<_HtmlSheet> {
  bool _rendered = true;
  bool _saving = false;
  String _note = '';

  /// 收一遍就够，来回切不用再解一次。
  late final String _md = htmlToMarkdown(widget.html);

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _note = '';
    });
    try {
      final String where = await saveToDownloads(
        name: widget.name,
        bytes: widget.file.readAsBytesSync(),
      );
      if (!mounted) return;
      setState(() => _note = '存到 $where');
    } catch (e) {
      if (!mounted) return;
      setState(() => _note = '存不下来：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.sizeOf(context).height * 0.8;
    return SheetCard(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SheetHead(title: widget.name, note: '网页输出'),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                _tab('渲染', _rendered, () => setState(() => _rendered = true)),
                const SizedBox(width: 6),
                _tab('原文', !_rendered, () => setState(() => _rendered = false)),
                const Spacer(),
                GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _saving ? C.rule : C.blue,
                      borderRadius: BorderRadius.circular(C.radiusSmall),
                    ),
                    child: Text(
                      _saving ? '正在存' : '存到手机',
                      style: const TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
            if (_note.isNotEmpty) ...<Widget>[
              const SizedBox(height: 7),
              Text(_note, style: C.monoSmall.copyWith(color: C.blue)),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.swap,
                switchInCurve: Motion.curve,
                child: _rendered
                    ? SingleChildScrollView(
                        key: const ValueKey<String>('md'),
                        child: SizedBox(
                          width: double.infinity,
                          child: MdText(
                            text: _md.isEmpty ? '这一页没有能读出来的文字。' : _md,
                            base: C.answer,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        key: const ValueKey<String>('raw'),
                        child: SelectableText(
                          widget.html,
                          style: C.output.copyWith(fontSize: 10.5),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? C.blueSoft : C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: on ? C.blue : C.rule2),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? C.blue : C.grey,
          ),
        ),
      ),
    );
  }
}
