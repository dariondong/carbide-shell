import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemChrome, SystemUiOverlayStyle;

/// 一套色板。浅色是暖白纸，深色是夜里的碳；两套用同一份名字，
/// 界面只认名字，换模式换的就是这一整张表。
class _Palette {
  const _Palette({
    required this.brightness,
    required this.paper,
    required this.card,
    required this.paper2,
    required this.ink,
    required this.body,
    required this.grey,
    required this.grey2,
    required this.rule,
    required this.rule2,
    required this.blue,
    required this.blueSoft,
    required this.onAccent,
    required this.knob,
    required this.onInk,
    required this.termBg,
    required this.outputInk,
    required this.ok,
    required this.danger,
    required this.dangerSoft,
    required this.approveBorder,
    required this.scrim,
    required this.snackBg,
    required this.snackFg,
    required this.select,
    required this.shadows,
  });

  final Brightness brightness;

  // 面
  final Color paper;
  final Color card;
  final Color paper2;

  // 字
  final Color ink;
  final Color body;
  final Color grey;
  final Color grey2;

  // 线
  final Color rule;
  final Color rule2;

  // 唯一的强调色，以及压在它上面的字
  final Color blue;
  final Color blueSoft;
  final Color onAccent;

  /// 开关上那颗圆点。浅色是白的，深色也是白的：它底下两条轨道都够深。
  final Color knob;

  /// 终端里的字：终端两边都是深色。
  final Color onInk;
  final Color termBg;

  /// 等宽输出的字色，比正文再轻一点。
  final Color outputInk;

  // 状态
  final Color ok;
  final Color danger;
  final Color dangerSoft;

  /// 审批卡那道淡蓝描边。
  final Color approveBorder;

  /// 盖住整页的半透明层。
  final Color scrim;

  final Color snackBg;
  final Color snackFg;
  final Color select;

  final List<BoxShadow> shadows;
}

const _Palette _light = _Palette(
  brightness: Brightness.light,
  paper: Color(0xFFFAF9F6),
  card: Color(0xFFFFFFFF),
  paper2: Color(0xFFF4F3EF),
  ink: Color(0xFF1A1C1F),
  body: Color(0xFF3A4048),
  grey: Color(0xFF6E7681),
  grey2: Color(0xFF9AA0A6),
  rule: Color(0xFFECEAE4),
  rule2: Color(0xFFDCD8D0),
  blue: Color(0xFF3355E8),
  blueSoft: Color(0xFFE8ECFC),
  onAccent: Color(0xFFFFFFFF),
  knob: Color(0xFFFFFFFF),
  onInk: Color(0xFFE9E7E1),
  termBg: Color(0xFF121417),
  outputInk: Color(0xFF5C636C),
  ok: Color(0xFF3FA96B),
  danger: Color(0xFFD7443E),
  dangerSoft: Color(0xFFFBEDEC),
  approveBorder: Color(0xFFD9DEF7),
  scrim: Color(0xF2181C23),
  snackBg: Color(0xFF1A1C1F),
  snackFg: Color(0xFFFFFFFF),
  select: Color(0x333355E8),
  shadows: <BoxShadow>[
    BoxShadow(color: Color(0x0F181C23), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x0D181C23), blurRadius: 16, offset: Offset(0, 6)),
  ],
);

/// 深色不是把浅色反过来：底色是带一点暖的碳黑，字是暖白，
/// 强调色提亮到能在深底上读出来，压在强调色上的字改成深墨。
const _Palette _dark = _Palette(
  brightness: Brightness.dark,
  paper: Color(0xFF14161A),
  card: Color(0xFF1B1E23),
  paper2: Color(0xFF22262C),
  ink: Color(0xFFE8E6E1),
  body: Color(0xFFC4C9D1),
  grey: Color(0xFF8F959E),
  grey2: Color(0xFF6F757E),
  rule: Color(0xFF262A31),
  rule2: Color(0xFF333842),
  blue: Color(0xFF8FA6FF),
  blueSoft: Color(0xFF232B49),
  onAccent: Color(0xFF0E1116),
  knob: Color(0xFFFFFFFF),
  onInk: Color(0xFFE9E7E1),
  termBg: Color(0xFF0E1013),
  outputInk: Color(0xFF9AA0A6),
  ok: Color(0xFF57C785),
  danger: Color(0xFFFF7B72),
  dangerSoft: Color(0xFF3A2224),
  approveBorder: Color(0xFF3B4570),
  scrim: Color(0xE6000000),
  snackBg: Color(0xFF2A2F37),
  snackFg: Color(0xFFF2F3F5),
  select: Color(0x558FA6FF),
  shadows: <BoxShadow>[
    BoxShadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
    BoxShadow(color: Color(0x4D000000), blurRadius: 16, offset: Offset(0, 6)),
  ],
);

_Palette _palette = _light;

/// Direction B: warm paper, white cards, one ink-blue accent, soft radius.
///
/// 颜色都从这里取。两套色板同名字，`C.useDark(true)` 把整张表换成夜里那套；
/// 换完把界面重画一遍就是深色。形状、字号、字距不随主题变。
class C {
  /// 色板换过一次就 +1。押在自己那层 rebuild 里的页面（比如设置子页）听它。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static bool get isDark => _palette.brightness == Brightness.dark;

  /// 换色板。返回是不是真的换了。
  static bool useDark(bool dark) {
    final _Palette next = dark ? _dark : _light;
    if (identical(next, _palette)) return false;
    _palette = next;
    revision.value += 1;
    return true;
  }

  // 面
  static Color get paper => _palette.paper;
  static Color get card => _palette.card;
  static Color get paper2 => _palette.paper2;

  // 字
  static Color get ink => _palette.ink;
  static Color get body => _palette.body;
  static Color get grey => _palette.grey;
  static Color get grey2 => _palette.grey2;

  // 线
  static Color get rule => _palette.rule;
  static Color get rule2 => _palette.rule2;

  // 强调
  static Color get blue => _palette.blue;
  static Color get blueSoft => _palette.blueSoft;
  static Color get onAccent => _palette.onAccent;
  static Color get knob => _palette.knob;

  // 终端
  static Color get onInk => _palette.onInk;
  static Color get termBg => _palette.termBg;
  static Color get outputInk => _palette.outputInk;

  // 状态
  static Color get ok => _palette.ok;
  static Color get danger => _palette.danger;
  static Color get dangerSoft => _palette.dangerSoft;
  static Color get approveBorder => _palette.approveBorder;
  static Color get scrim => _palette.scrim;
  static Color get snackBg => _palette.snackBg;
  static Color get snackFg => _palette.snackFg;

  static const double radius = 14;
  static const double radiusSmall = 10;

  static List<BoxShadow> get softShadow => _palette.shadows;

  static const String monoFamily = 'monospace';

  static TextStyle get label => TextStyle(
        fontSize: 10,
        letterSpacing: 1.4,
        color: grey,
        fontWeight: FontWeight.w600,
        height: 1.4,
      );

  static TextStyle get mono => TextStyle(
        fontFamily: monoFamily,
        fontSize: 12,
        height: 1.45,
        color: ink,
      );

  static TextStyle get monoSmall => TextStyle(
        fontFamily: monoFamily,
        fontSize: 10.5,
        height: 1.5,
        color: grey,
      );

  static TextStyle get output => TextStyle(
        fontFamily: monoFamily,
        fontSize: 11,
        height: 1.5,
        color: outputInk,
      );

  static TextStyle get ask => TextStyle(
        fontSize: 16,
        height: 1.5,
        color: ink,
        letterSpacing: -0.1,
      );

  static TextStyle get answer => TextStyle(
        fontSize: 13.5,
        height: 1.55,
        color: body,
      );

  /// 状态栏、导航栏全透明，图标跟着底色走：深色底要浅色图标。
  static void applySystemChrome() {
    final bool dark = isDark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: const Color(0x00000000),
      systemNavigationBarDividerColor: const Color(0x00000000),
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    ));
  }

  static ThemeData theme() {
    final ColorScheme scheme = ColorScheme(
      brightness: _palette.brightness,
      primary: blue,
      onPrimary: onAccent,
      secondary: ink,
      onSecondary: paper,
      surface: card,
      onSurface: ink,
      error: danger,
      onError: onAccent,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: _palette.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      canvasColor: paper,
      dividerColor: rule,
      splashFactory: NoSplash.splashFactory,
      highlightColor: const Color(0x00000000),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: blue,
        selectionColor: _palette.select,
        selectionHandleColor: blue,
      ),
      textTheme: TextTheme(
        bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.45),
        bodySmall: TextStyle(fontSize: 12, color: grey, height: 1.45),
        titleMedium: TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        isDense: true,
        hintStyle: TextStyle(fontSize: 13, color: grey2),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        elevation: 0,
        shadowColor: const Color(0x29181C23),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: snackBg,
        contentTextStyle: TextStyle(color: snackFg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
      ),
      // 翻页用自己那一层：淡入 + 往上抬一点，比默认的左右滑安静。
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: SoftPageTransitions(),
          TargetPlatform.windows: SoftPageTransitions(),
          TargetPlatform.linux: SoftPageTransitions(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// The one card shape used everywhere.
  static BoxDecoration cardDecoration({Color? border, bool shadow = true}) =>
      BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? rule),
        boxShadow: shadow ? softShadow : const <BoxShadow>[],
      );
}

/// 设置里那一条要不要深色：`system` 跟系统亮度走，`light` / `dark` 是钉死的。
bool themeIsDark(String mode) {
  if (mode == 'dark') return true;
  if (mode == 'light') return false;
  return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
}

/// 新页淡入、往上抬一点；系统开了「减少动态效果」时直接换页。
class SoftPageTransitions extends PageTransitionsBuilder {
  const SoftPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return child;
    final Animation<double> fade =
        CurvedAnimation(parent: animation, curve: Curves.easeOutQuart);
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.022),
          end: Offset.zero,
        ).animate(fade),
        child: child,
      ),
    );
  }
}
