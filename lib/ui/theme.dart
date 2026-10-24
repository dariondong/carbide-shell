import 'package:flutter/material.dart';

/// The palette and the type scale from DESIGN.md. Nothing else may be used.
class C {
  static const Color paper = Color(0xFFF4F2ED);
  static const Color paper2 = Color(0xFFEDEAE3);
  static const Color ink = Color(0xFF111315);
  static const Color body = Color(0xFF2A2F33);
  static const Color grey = Color(0xFF63686C);
  static const Color grey2 = Color(0xFF787870);
  static const Color rule = Color(0xFFD5D0C4);
  static const Color rule2 = Color(0xFFBDB7A8);
  static const Color blue = Color(0xFF1B4BC4);
  static const Color onInk = Color(0xFFE9E7E1);

  static const String monoFamily = 'monospace';

  static const TextStyle label = TextStyle(
    fontSize: 10,
    letterSpacing: 1.8,
    color: grey,
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
    fontSize: 11.5,
    height: 1.45,
    color: Color(0xFF3A4045),
  );

  static const TextStyle ask = TextStyle(
    fontSize: 16,
    height: 1.45,
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
      primary: ink,
      onPrimary: paper,
      secondary: blue,
      onSecondary: paper,
      surface: paper,
      onSurface: ink,
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
        selectionColor: Color(0x331B4BC4),
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
      dialogTheme: const DialogThemeData(
        backgroundColor: paper,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        elevation: 0,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: ink,
        contentTextStyle: TextStyle(color: paper),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
