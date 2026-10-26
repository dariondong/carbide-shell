import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/markdown.dart';
import 'theme.dart';

/// 把模型输出按 Markdown 画出来。
///
/// 标题、段落、列表、引用、分隔线、围栏代码与表格各占一块；行内的粗体、
/// 斜体、行内代码、删除线与链接都认。颜色与圆角只取 [C]，不多一样样子。
class MdText extends StatefulWidget {
  const MdText({
    super.key,
    required this.text,
    this.streaming = false,
    this.base,
  });

  final String text;

  /// 正在逐字输出：末尾挂一个蓝方块当光标。
  final bool streaming;

  final TextStyle? base;

  @override
  State<MdText> createState() => _MdTextState();
}

class _MdTextState extends State<MdText> {
  final List<TapGestureRecognizer> _taps = <TapGestureRecognizer>[];

  /// 上一遍拆出来的那些块。字没变就直接拿来回这一份，
  /// 长对话里几十条回答不用每秒重拆十几次。
  List<Widget>? _kids;
  String? _source;
  TextStyle? _base;

  @override
  void dispose() {
    _dropTaps();
    super.dispose();
  }

  void _dropTaps() {
    for (final TapGestureRecognizer tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle base = widget.base ?? C.answer;
    final String source = widget.streaming ? '${widget.text} ▍' : widget.text;
    if (_kids != null && _source == source && _base == base) {
      // 同一个对象交回去，Flutter 会连子树都不用走。
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: _kids!);
    }
    _dropTaps();
    final List<MdBlock> blocks = parseMarkdown(source);
    final List<Widget> kids = <Widget>[];
    for (int i = 0; i < blocks.length; i += 1) {
      if (i > 0) kids.add(const SizedBox(height: 8));
      kids.add(_block(blocks[i], base));
    }
    _kids = kids;
    _source = source;
    _base = base;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: kids);
  }

  Widget _block(MdBlock b, TextStyle base) {
    switch (b.kind) {
      case MdBlockKind.heading:
        final double size = switch (b.level) {
          1 => 17.0,
          2 => 15.5,
          3 => 14.5,
          _ => 13.5,
        };
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: _rich(
            b.text,
            base.copyWith(
              fontSize: size,
              fontWeight: FontWeight.w700,
              color: C.ink,
              height: 1.4,
            ),
          ),
        );
      case MdBlockKind.paragraph:
        return _rich(b.text, base);
      case MdBlockKind.code:
        return _code(b.text);
      case MdBlockKind.rule:
        return Container(height: 1, color: C.rule);
      case MdBlockKind.quote:
        return Container(
          padding: const EdgeInsets.only(left: 11),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: C.rule2, width: 2)),
          ),
          child: _rich(b.text, base.copyWith(color: C.grey)),
        );
      case MdBlockKind.bullet:
        return _item('•', b, base);
      case MdBlockKind.ordered:
        return _item('${b.number}.', b, base);
      case MdBlockKind.table:
        return _table(b.rows, base);
    }
  }

  Widget _item(String mark, MdBlock b, TextStyle base) {
    return Padding(
      padding: EdgeInsets.only(left: (b.level - 1) * 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 20,
            child: Text(mark, style: base.copyWith(color: C.grey2)),
          ),
          Expanded(child: _rich(b.text, base)),
        ],
      ),
    );
  }

  Widget _code(String body) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
      decoration: BoxDecoration(
        color: C.paper2,
        borderRadius: BorderRadius.circular(C.radiusSmall),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(body, style: C.mono.copyWith(color: C.ink, height: 1.5)),
      ),
    );
  }

  Widget _table(List<List<String>> rows, TextStyle base) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final int cols = rows.first.length;
    final TextStyle head = base.copyWith(fontWeight: FontWeight.w700, color: C.ink);
    return Table(
      border: TableBorder.all(color: C.rule, width: 1),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: <int, TableColumnWidth>{
        for (int i = 0; i < cols; i += 1) i: const FlexColumnWidth(),
      },
      children: <TableRow>[
        for (int r = 0; r < rows.length; r += 1)
          TableRow(
            children: <Widget>[
              for (int c = 0; c < cols; c += 1)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: _rich(
                    c < rows[r].length ? rows[r][c] : '',
                    r == 0 ? head : base,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _rich(String source, TextStyle base) {
    if (source.isEmpty) return const SizedBox.shrink();
    return Text.rich(
      TextSpan(children: <TextSpan>[for (final MdSpan s in parseInline(source)) _span(s, base)]),
      style: base,
    );
  }

  TextSpan _span(MdSpan s, TextStyle base) {
    switch (s.kind) {
      case MdSpanKind.plain:
        return TextSpan(text: s.text, style: base);
      case MdSpanKind.bold:
        return TextSpan(
          text: s.text,
          style: base.copyWith(fontWeight: FontWeight.w700, color: C.ink),
        );
      case MdSpanKind.italic:
        return TextSpan(text: s.text, style: base.copyWith(fontStyle: FontStyle.italic));
      case MdSpanKind.strike:
        return TextSpan(
          text: s.text,
          style: base.copyWith(decoration: TextDecoration.lineThrough),
        );
      case MdSpanKind.code:
        return TextSpan(
          text: s.text,
          style: base.copyWith(
            fontFamily: C.monoFamily,
            fontSize: (base.fontSize ?? 13.5) - 1.5,
            backgroundColor: C.paper2,
            color: C.ink,
          ),
        );
      case MdSpanKind.link:
        final TapGestureRecognizer tap = TapGestureRecognizer()
          ..onTap = () => openUrl(s.href);
        _taps.add(tap);
        return TextSpan(
          text: s.text,
          style: base.copyWith(color: C.blue, decoration: TextDecoration.underline),
          recognizer: tap,
        );
    }
  }

}

/// 打开一个地址：交给外面的浏览器；打不开就算了，字还留在原地。
Future<void> openUrl(String href) async {
  final Uri? uri = Uri.tryParse(href);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // 打不开就算了，地址还在字里。
  }
}

/// 一段不画 Markdown、只把地址认出来的字：工具输出那种等宽块用它。
class LinkText extends StatefulWidget {
  const LinkText({super.key, required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  final List<TapGestureRecognizer> _taps = <TapGestureRecognizer>[];

  /// 字没变就把上回那批 span 交回去，跟 [MdText] 一个路数。
  List<InlineSpan>? _kids;
  String? _source;
  TextStyle? _style;

  @override
  void dispose() {
    _dropTaps();
    super.dispose();
  }

  void _dropTaps() {
    for (final TapGestureRecognizer tap in _taps) {
      tap.dispose();
    }
    _taps.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (_kids != null && _source == widget.text && _style == widget.style) {
      return Text.rich(TextSpan(children: _kids), style: widget.style);
    }
    _dropTaps();
    final TextStyle base = widget.style;
    final List<InlineSpan> kids = <InlineSpan>[];
    for (final MdSpan s in linkifyPlain(widget.text)) {
      if (s.kind != MdSpanKind.link) {
        kids.add(TextSpan(text: s.text, style: base));
        continue;
      }
      final TapGestureRecognizer tap = TapGestureRecognizer()
        ..onTap = () => openUrl(s.href);
      _taps.add(tap);
      kids.add(TextSpan(
        text: s.text,
        style: base.copyWith(
          color: C.blue,
          decoration: TextDecoration.underline,
          decorationColor: C.blue,
        ),
        recognizer: tap,
      ));
    }
    _kids = kids;
    _source = widget.text;
    _style = base;
    return Text.rich(TextSpan(children: kids), style: base);
  }
}
