import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/html.dart';
import '../data/export.dart';
import '../data/hosts.dart';
import '../data/temp_files.dart';
import '../tools/ssh_tools.dart';
import '../tools/temp_tools.dart';
import 'components.dart';
import 'md_text.dart';
import 'motion.dart';
import 'theme.dart';

/// 临时文件区。模型写进来的、你自己加进来的都在这儿，一个文件传到主机上只要点两下。
class TempFilesPage extends StatefulWidget {
  const TempFilesPage({
    super.key,
    required this.files,
    required this.hosts,
    required this.pool,
  });

  final TempFiles files;
  final HostStore hosts;
  final SshPool pool;

  @override
  State<TempFilesPage> createState() => _TempFilesPageState();
}

class _TempFilesPageState extends State<TempFilesPage> {
  List<TempFile> _items = <TempFile>[];

  @override
  void initState() {
    super.initState();
    _items = widget.files.list();
  }

  void _load() {
    if (!mounted) return;
    setState(() => _items = widget.files.list());
  }

  int get _total {
    int sum = 0;
    for (final TempFile f in _items) {
      sum += f.size;
    }
    return sum;
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
    );
    if (picked == null || picked.files.isEmpty) return;
    int added = 0;
    for (final PlatformFile f in picked.files) {
      final List<int>? bytes = f.bytes;
      if (bytes == null) continue;
      try {
        await widget.files.save(f.name, bytes);
        added += 1;
      } catch (e) {
        _toast('${f.name} 没进来：$e');
      }
    }
    _load();
    if (added > 0) _toast('加进来 $added 个文件。');
  }

  /// 删掉能撤回：字节先留在手里，撤销时按原路径写回去。
  Future<void> _remove(TempFile f) async {
    final File? local = widget.files.fileOf(f.path);
    List<int>? keep;
    if (local != null && local.existsSync() && f.size <= TempFiles.maxBytes) {
      keep = await local.readAsBytes();
    }
    final bool ok = await widget.files.remove(f.path);
    if (!ok) {
      _toast('这个文件已经不在了。');
      _load();
      return;
    }
    _load();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('删掉了 ${f.name}'),
        action: keep == null
            ? null
            : SnackBarAction(
                label: '撤销',
                textColor: C.card,
                onPressed: () async {
                  await widget.files.put(f.path, keep!);
                  _load();
                },
              ),
      ),
    );
  }

  Future<void> _clearAll() async {
    if (_items.isEmpty) return;
    final bool? ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => SheetCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SheetHead(
              title: '清空临时文件区',
              note: '${_items.length} 个文件 · ${tempSize(_total)}',
            ),
            const SizedBox(height: 14),
            const Text('这一块里的文件都会删掉，删完从服务器那头找不回来。',
                style: TextStyle(fontSize: 12.5, height: 1.55, color: C.grey)),
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Expanded(
                  child: SquareButton(
                    label: '留着',
                    tone: 'ink',
                    onPressed: () => Navigator.of(ctx).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SquareButton(
                    label: '清空',
                    filled: true,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await widget.files.clear();
    _load();
    _toast('清空了。');
  }

  /// 打开一个文件：图片放大看，Markdown 和 HTML 直接渲染，其余看原文，都能存到下载目录。
  Future<void> _preview(TempFile f) async {
    final File? local = widget.files.fileOf(f.path);
    if (local == null || !local.existsSync()) {
      _toast('这个文件已经不在了。');
      return;
    }
    final String? text = f.isImage ? null : await widget.files.readText(f.path);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => _PreviewSheet(
        item: f,
        local: local,
        text: text,
      ),
    );
  }

  Future<void> _upload(TempFile f) async {
    if (widget.hosts.hosts.isEmpty) {
      _toast('还没有主机，先在主机页加一台。');
      return;
    }
    final String? done = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => _UploadSheet(
        item: f,
        files: widget.files,
        hosts: widget.hosts,
        pool: widget.pool,
      ),
    );
    if (done == null || done.isEmpty) return;
    _toast('传到了 $done');
  }

  /// 从服务器取一个下来：先挑主机、进目录，再点那个文件。
  Future<void> _fetch() async {
    if (widget.hosts.hosts.isEmpty) {
      _toast('还没有主机，先在主机页加一台。');
      return;
    }
    final String? got = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (BuildContext ctx) => _FetchSheet(
        files: widget.files,
        hosts: widget.hosts,
        pool: widget.pool,
      ),
    );
    if (got == null || got.isEmpty) return;
    _load();
    _toast('取回来了：$got');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: C.paper,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              height: 56,
              padding: const EdgeInsets.fromLTRB(6, 0, 10, 0),
              decoration: const BoxDecoration(
                color: C.card,
                border: Border(bottom: BorderSide(color: C.rule)),
              ),
              child: Row(
                children: <Widget>[
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, size: 19, color: C.ink),
                  ),
                  const Text('临时文件',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Text('${_items.length} 个 · ${tempSize(_total)}', style: C.monoSmall),
                  const Spacer(),
                  GestureDetector(
                    onTap: _fetch,
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 8),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.paper2,
                        borderRadius: BorderRadius.circular(C.radiusSmall),
                      ),
                      child: const Icon(Icons.cloud_download_outlined,
                          size: 17, color: C.ink),
                    ),
                  ),
                  GestureDetector(
                    onTap: _add,
                    child: Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: C.blue,
                        borderRadius: BorderRadius.circular(C.radiusSmall),
                      ),
                      child: const Icon(Icons.add, size: 17, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.swap,
                switchInCurve: Motion.curve,
                child: _items.isEmpty
                    ? KeyedSubtree(key: const ValueKey<String>('empty'), child: _empty())
                    : ListView(
                        key: const ValueKey<String>('list'),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
                        children: <Widget>[
                          FadeSlideIn(
                            child: CardBox(
                              padding: EdgeInsets.zero,
                              child: Column(
                                children: <Widget>[
                                  for (int i = 0; i < _items.length; i += 1) ...<Widget>[
                                    if (i > 0) const RuleLine(),
                                    FadeSlideIn(
                                      delay: Motion.stagger * (i < 9 ? i : 9),
                                      lift: 6,
                                      child: _row(_items[i]),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Center(
                            child: TextButton(
                              onPressed: _clearAll,
                              style: TextButton.styleFrom(
                                foregroundColor: C.grey,
                                textStyle: const TextStyle(fontSize: 12.5),
                              ),
                              child: const Text('清空临时文件'),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('这里还没有文件',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, height: 1.4)),
          const SizedBox(height: 8),
          const Text(
            '模型在这里写文件，你也可以把手机上的文件加进来。写好从这里传到服务器。',
            style: C.answer,
          ),
          const SizedBox(height: 18),
          SquareButton(label: '加一个文件', filled: true, onPressed: _add),
        ],
      ),
    );
  }

  Widget _row(TempFile f) {
    return InkWell(
      onTap: () => _preview(f),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: <Widget>[
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: C.paper2,
                borderRadius: BorderRadius.circular(C.radiusSmall),
              ),
              child: Icon(_icon(f), size: 16, color: C.grey),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(f.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: C.ink)),
                  const SizedBox(height: 2),
                  Text('${tempSize(f.size)} · ${_when(f.modified)}', style: C.monoSmall),
                ],
              ),
            ),
            _iconButton(Icons.cloud_upload_outlined, '传到服务器', () => _upload(f)),
            _iconButton(Icons.delete_outline, '删除', () => _remove(f)),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: PressScale(
        onTap: onTap,
        scale: 0.9,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 17, color: C.grey),
        ),
      ),
    );
  }

  IconData _icon(TempFile f) {
    if (f.isImage) return Icons.image_outlined;
    if (f.isMarkdown) return Icons.article_outlined;
    if (f.isHtml) return Icons.language;
    if (f.isText) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }

  static String _when(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    final DateTime local = t.toLocal();
    return '${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }
}

/// 传到服务器。主机一条条点，路径先填好再改。
class _UploadSheet extends StatefulWidget {
  const _UploadSheet({
    required this.item,
    required this.files,
    required this.hosts,
    required this.pool,
  });

  final TempFile item;
  final TempFiles files;
  final HostStore hosts;
  final SshPool pool;

  @override
  State<_UploadSheet> createState() => _UploadSheetState();
}

class _UploadSheetState extends State<_UploadSheet> {
  late final TextEditingController _path =
      TextEditingController(text: '/tmp/${widget.item.name}');
  String _hostId = '';
  bool _busy = false;
  String _error = '';
  UploadCancel? _cancel;
  int _sent = 0;
  int _total = 0;
  int _pct = 0;

  @override
  void initState() {
    super.initState();
    if (widget.hosts.hosts.length == 1) _hostId = widget.hosts.hosts.first.id;
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  /// 百分比没变就不重画，小文件一多也不会闪。
  void _progress(int sent, int total) {
    if (!mounted) return;
    final int pct = total <= 0 ? 100 : (sent * 100 ~/ total);
    if (pct == _pct && sent != total) return;
    setState(() {
      _pct = pct;
      _sent = sent;
      _total = total;
    });
  }

  Future<void> _run() async {
    if (_busy) return;
    final HostEntry? entry = widget.hosts.byId(_hostId);
    if (entry == null) {
      setState(() => _error = '先点一下主机。');
      return;
    }
    final File? local = widget.files.fileOf(widget.item.path);
    if (local == null || !local.existsSync()) {
      setState(() => _error = '这个文件已经不在了。');
      return;
    }
    final UploadCancel cancel = UploadCancel();
    setState(() {
      _busy = true;
      _error = '';
      _cancel = cancel;
      _sent = 0;
      _total = widget.item.size;
      _pct = 0;
    });
    try {
      final TempUpload done = await sftpUpload(
        widget.pool,
        entry,
        local,
        _path.text,
        cancel: cancel,
        onProgress: _progress,
      );
      if (!mounted) return;
      Navigator.of(context).pop('${done.host}:${done.path}');
    } on UploadCancelled {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _cancel = null;
        _error = '停下了。服务器上可能留了一个没传完的文件。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _cancel = null;
        _error = '传不上去：$e';
      });
    }
  }

  void _stop() {
    if (_busy) {
      _cancel?.cancel();
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final List<HostEntry> hosts = widget.hosts.hosts;
    final HostEntry? picked = widget.hosts.byId(_hostId);
    return SheetCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SheetHead(
            title: '传到服务器',
            note: '${widget.item.path} · ${tempSize(widget.item.size)}',
          ),
          const SizedBox(height: 16),
          const SectionLabel('主机'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final HostEntry h in hosts)
                _hostChip(h, h.id == _hostId),
            ],
          ),
          const SizedBox(height: 8),
          Text(picked == null ? '还没选主机' : picked.host,
              style: C.monoSmall.copyWith(color: picked == null ? C.grey2 : C.grey)),
          const SizedBox(height: 16),
          const SectionLabel('远端路径'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: C.paper2,
              borderRadius: BorderRadius.circular(C.radiusSmall),
            ),
            child: TextField(
              controller: _path,
              enabled: !_busy,
              style: C.mono.copyWith(fontSize: 13),
              decoration: const InputDecoration(hintText: '/tmp/文件名'),
            ),
          ),
          if (_busy) ...<Widget>[
            const SizedBox(height: 16),
            Row(
              children: <Widget>[
                Text('正在传 · $_pct%',
                    style: C.monoSmall.copyWith(color: C.blue)),
                const Spacer(),
                Text('${tempSize(_sent)} / ${tempSize(_total)}',
                    style: C.monoSmall),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _pct / 100),
                duration: Motion.swap,
                curve: Motion.curve,
                builder: (BuildContext ctx, double value, Widget? child) =>
                    LinearProgressIndicator(
                  value: value,
                  minHeight: 4,
                  backgroundColor: C.rule,
                  color: C.blue,
                ),
              ),
            ),
          ],
          if (_error.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error,
                style: const TextStyle(
                    fontSize: 12, height: 1.5, color: Color(0xFFD7443E))),
          ],
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: SquareButton(
                  label: '取消',
                  tone: 'ink',
                  onPressed: _stop,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SquareButton(
                  label: _busy ? '正在传' : '上传',
                  filled: true,
                  onPressed: _busy ? null : _run,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hostChip(HostEntry h, bool on) {
    return GestureDetector(
      onTap: _busy ? null : () => setState(() => _hostId = h.id),
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? C.blue : C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: on ? C.blue : C.rule2),
        ),
        child: Text(
          h.name,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? Colors.white : C.ink,
          ),
        ),
      ),
    );
  }
}

/// 看一个文件：图片放大、Markdown / HTML 渲染、其余看原文，右上角能存到下载目录。
class _PreviewSheet extends StatefulWidget {
  const _PreviewSheet({
    required this.item,
    required this.local,
    required this.text,
  });

  final TempFile item;
  final File local;

  /// 文本内容；图片和读不出来的二进制是 null。
  final String? text;

  @override
  State<_PreviewSheet> createState() => _PreviewSheetState();
}

class _PreviewSheetState extends State<_PreviewSheet> {
  bool _rendered = true;
  bool _saving = false;
  String _where = '';
  String _error = '';

  bool get _canRender => widget.item.isMarkdown || widget.item.isHtml;

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _where = '';
      _error = '';
    });
    try {
      final Uint8List bytes = await widget.local.readAsBytes();
      final String where = await saveToDownloads(
        name: widget.item.name,
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _where = '存到 $where');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '存不下来：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double height = MediaQuery.sizeOf(context).height * 0.82;
    return SheetCard(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SheetHead(
              title: widget.item.name,
              note: '${widget.item.path} · ${tempSize(widget.item.size)}',
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                if (_canRender) ...<Widget>[
                  _tab('渲染', _rendered, () => setState(() => _rendered = true)),
                  const SizedBox(width: 6),
                  _tab('原文', !_rendered, () => setState(() => _rendered = false)),
                ],
                const Spacer(),
                _downloadBtn(),
              ],
            ),
            if (_where.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(_where, style: C.monoSmall.copyWith(color: C.blue)),
            ],
            if (_error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Text(_error,
                  style: const TextStyle(
                      fontSize: 12, height: 1.5, color: Color(0xFFD7443E))),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: AnimatedSwitcher(
                duration: Motion.swap,
                switchInCurve: Motion.curve,
                child: KeyedSubtree(
                  key: ValueKey<String>(
                      '${widget.item.path}-${_rendered ? 'r' : 't'}'),
                  child: _body(),
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

  Widget _downloadBtn() {
    return GestureDetector(
      onTap: _saving ? null : _save,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _saving ? C.rule : C.blue,
          borderRadius: BorderRadius.circular(C.radiusSmall),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_saving)
              const SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white),
              )
            else
              const Icon(Icons.download_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              _saving ? '正在存' : '下载',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (widget.item.isImage) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: C.paper2,
          borderRadius: BorderRadius.circular(C.radiusSmall),
        ),
        child: InteractiveViewer(
          maxScale: 5,
          child: Center(
            child: Image.file(widget.local, fit: BoxFit.contain, gaplessPlayback: true),
          ),
        ),
      );
    }
    final String? text = widget.text;
    if (text == null) {
      return Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: C.paper2,
          borderRadius: BorderRadius.circular(C.radiusSmall),
        ),
        child: const Text(
          '这是二进制文件，内容读不出来。\n可以下载到手机上，或者传到服务器。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, height: 1.7, color: C.grey),
        ),
      );
    }
    final String body = text.isEmpty ? '（空文件）' : text;
    if (_canRender && _rendered) {
      final String md = widget.item.isHtml ? htmlToMarkdown(body) : body;
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: C.rule),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: MdText(text: md.isEmpty ? '（空文件）' : md),
        ),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: C.paper2,
        borderRadius: BorderRadius.circular(C.radiusSmall),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          body,
          style: C.mono.copyWith(fontSize: 11.5, height: 1.6),
        ),
      ),
    );
  }
}

/// 从服务器取一个：挑主机、进目录、点那个文件，落到临时文件区。
///
/// 只列名字，不预读内容；点下去才开始走 sftp，块块落盘，失败就说失败。
class _FetchSheet extends StatefulWidget {
  const _FetchSheet({
    required this.files,
    required this.hosts,
    required this.pool,
  });

  final TempFiles files;
  final HostStore hosts;
  final SshPool pool;

  @override
  State<_FetchSheet> createState() => _FetchSheetState();
}

class _FetchSheetState extends State<_FetchSheet> {
  final TextEditingController _path = TextEditingController(text: '~');
  String _hostId = '';
  List<RemoteItem> _items = <RemoteItem>[];
  bool _loading = false;
  bool _busy = false;
  String _picking = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (widget.hosts.hosts.length == 1) _hostId = widget.hosts.hosts.first.id;
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  String get _base {
    final String path = _path.text.trim();
    if (path.isEmpty) return '';
    return path.endsWith('/') ? path : '$path/';
  }

  Future<void> _open() async {
    final HostEntry? entry = widget.hosts.byId(_hostId);
    if (entry == null) return;
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final List<RemoteItem> items = await remoteList(widget.pool, entry, _path.text);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = <RemoteItem>[];
        _error = '列不出来：$e';
      });
    }
  }

  void _up() {
    final String path = _path.text.trim();
    if (path.isEmpty || path == '/' || path == '~') return;
    final String trimmed = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    final int cut = trimmed.lastIndexOf('/');
    final String next = cut <= 0 ? '/' : trimmed.substring(0, cut);
    setState(() => _path.text = next);
    _open();
  }

  Future<void> _enter(RemoteItem item) async {
    if (item.dir) {
      setState(() => _path.text = '$_base${item.name}/');
      await _open();
      return;
    }
    final HostEntry? entry = widget.hosts.byId(_hostId);
    if (entry == null) {
      setState(() => _error = '先点一下主机。');
      return;
    }
    setState(() {
      _busy = true;
      _picking = item.name;
      _error = '';
    });
    try {
      final File target = widget.files.freshNamed(item.name);
      final int bytes =
          await sftpDownload(widget.pool, entry, '$_base${item.name}', target);
      if (!mounted) return;
      final String rel = target.path.substring(widget.files.root.path.length + 1);
      Navigator.of(context).pop('$rel（${tempSize(bytes)}）');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _picking = '';
        _error = '取不回来：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<HostEntry> hosts = widget.hosts.hosts;
    final double height = MediaQuery.sizeOf(context).height * 0.74;
    return SheetCard(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SheetHead(
              title: '从服务器取',
              note: '点目录进去，点文件取回来',
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final HostEntry h in hosts) _hostChip(h),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                _pathChip('上一级', _busy ? null : _up),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: C.paper2,
                      borderRadius: BorderRadius.circular(C.radiusSmall),
                    ),
                    child: TextField(
                      controller: _path,
                      enabled: !_busy,
                      style: C.mono.copyWith(fontSize: 12),
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _open(),
                      decoration: const InputDecoration(hintText: '/var/log'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _pathChip('去', _busy ? null : _open),
              ],
            ),
            if (_error.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Text(_error,
                  style: const TextStyle(
                      fontSize: 12, height: 1.5, color: Color(0xFFD7443E))),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 1.8, color: C.blue),
                      ),
                    )
                  : _items.isEmpty
                      ? Center(
                          child: Text('这个目录是空的，或者读不了。',
                              style: C.monoSmall.copyWith(color: C.grey2)),
                        )
                      : ListView.builder(
                          itemCount: _items.length,
                          itemBuilder: (BuildContext ctx, int i) => _row(_items[i]),
                        ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: SquareButton(
                    label: '关闭',
                    tone: 'ink',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SquareButton(
                    label: _busy ? '正在取' : '刷新',
                    filled: true,
                    onPressed: _busy ? null : _open,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hostChip(HostEntry h) {
    final bool on = h.id == _hostId;
    return GestureDetector(
      onTap: _busy
          ? null
          : () {
              setState(() => _hostId = h.id);
              _open();
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? C.blue : C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: on ? C.blue : C.rule2),
        ),
        child: Text(h.name,
            style: TextStyle(fontSize: 12, color: on ? Colors.white : C.ink)),
      ),
    );
  }

  Widget _pathChip(String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(C.radiusSmall),
          border: Border.all(color: C.rule2),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 12, color: onTap == null ? C.grey2 : C.ink)),
      ),
    );
  }

  Widget _row(RemoteItem item) {
    final bool busy = _busy && _picking == item.name;
    return InkWell(
      onTap: _busy ? null : () => _enter(item),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
        child: Row(
          children: <Widget>[
            Icon(
              item.dir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
              size: 15,
              color: item.dir ? C.blue : C.grey,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: C.mono.copyWith(fontSize: 12, color: C.ink),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: C.blue),
              )
            else if (!item.dir)
              const Icon(Icons.download_rounded, size: 15, color: C.grey2),
          ],
        ),
      ),
    );
  }
}
