import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

/// Direction B: warm paper, white cards, one ink-blue accent, soft radius.
class C {
  // Surfaces
  static const Color paper = Color(0xFFFAF9F6); // page
  static const Color card = Color(0xFFFFFFFF); // raised card
  static const Color paper2 = Color(0xFFF4F3EF); // inset / code block

  // Ink
  static const Color ink = Color(0xFF1A1C1F);
  static const Color body = Color(0xFF3A4048);
  static const Color grey = Color(0xFF6E7681);
  static const Color grey2 = Color(0xFF9AA0A6);

  // Lines
  static const Color rule = Color(0xFFECEAE4);
  static const Color rule2 = Color(0xFFDCD8D0);

  // One accent
  static const Color blue = Color(0xFF3355E8);
  static const Color blueSoft = Color(0xFFE8ECFC);

  // Terminal stays dark: it is a terminal.
  static const Color onInk = Color(0xFFE9E7E1);
  static const Color termBg = Color(0xFF121417);

  static const double radius = 14;
  static const double radiusSmall = 10;

  static List<BoxShadow> get softShadow => const <BoxShadow>[
        BoxShadow(color: Color(0x0F181C23), blurRadius: 2, offset: Offset(0, 1)),
        BoxShadow(color: Color(0x0D181C23), blurRadius: 16, offset: Offset(0, 6)),
      ];

  static const String monoFamily = 'monospace';

  static const TextStyle label = TextStyle(
    fontSize: 10,
    letterSpacing: 1.4,
    color: grey,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle mono = TextStyle(
    fontFamily: monoFamily,
    fontSize: 12,
    height: 1.45,
    color: ink,
  );

  static const TextStyle monoSmall = TextStyle(
    fontFamily: monoFamily,
    fontSize: 10.5,
    height: 1.5,
    color: grey,
  );

  static const TextStyle output = TextStyle(
    fontFamily: monoFamily,
    fontSize: 11,
    height: 1.5,
    color: Color(0xFF5C636C),
  );

  static const TextStyle ask = TextStyle(
    fontSize: 16,
    height: 1.5,
    color: ink,
    letterSpacing: -0.1,
  );

  static const TextStyle answer = TextStyle(
    fontSize: 13.5,
    height: 1.55,
    color: body,
  );

  static ThemeData theme() {
    final ColorScheme scheme = const ColorScheme.light(
      primary: blue,
      onPrimary: Colors.white,
      secondary: ink,
      onSecondary: Colors.white,
      surface: card,
      onSurface: ink,
      error: Color(0xFFD7443E),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      canvasColor: paper,
      dividerColor: rule,
      splashFactory: NoSplash.splashFactory,
      highlightColor: const Color(0x00000000),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: blue,
        selectionColor: Color(0x333355E8),
        selectionHandleColor: blue,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.45),
        bodySmall: TextStyle(fontSize: 12, color: grey, height: 1.45),
        titleMedium: TextStyle(fontSize: 15, color: ink, fontWeight: FontWeight.w700),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: InputBorder.none,
        isDense: true,
        hintStyle: TextStyle(fontSize: 13, color: grey2),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        elevation: 0,
        shadowColor: const Color(0x1A181C23),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: const TextStyle(color: Colors.white),
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
  static BoxDecoration cardDecoration({Color border = rule, bool shadow = true}) =>
      BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border),
        boxShadow: shadow ? softShadow : const <BoxShadow>[],
      );
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
