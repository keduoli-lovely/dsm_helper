import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 设计语言参考「飞牛 fnOS」App：柔和蓝紫渐变背景、白色大圆角卡片、
/// 蓝色主色、克制的阴影与大量留白。
@immutable
class AppColors {
  final bool isDark;
  final Color bgTop;
  final Color bgMid;
  final Color bgBottom;
  final Color surface;
  final Color surfaceAlt;
  final Color surfaceSunken;
  final Color primary;
  final Color primaryDeep;
  final Color onPrimary;
  final Color mint;
  final Color orange;
  final Color pink;
  final Color purple;
  final Color sky;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color success;
  final Color warning;
  final Color danger;
  final Color border;

  const AppColors({
    required this.isDark,
    required this.bgTop,
    required this.bgMid,
    required this.bgBottom,
    required this.surface,
    required this.surfaceAlt,
    required this.surfaceSunken,
    required this.primary,
    required this.primaryDeep,
    required this.onPrimary,
    required this.mint,
    required this.orange,
    required this.pink,
    required this.purple,
    required this.sky,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.success,
    required this.warning,
    required this.danger,
    required this.border,
  });

  static const AppColors light = AppColors(
    isDark: false,
    bgTop: Color(0xFFE7ECFB),
    bgMid: Color(0xFFF1F4FD),
    bgBottom: Color(0xFFF8F9FC),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF4F6FC),
    surfaceSunken: Color(0xFFEDF0F8),
    primary: Color(0xFF2E6BFF),
    primaryDeep: Color(0xFF1B4AE0),
    onPrimary: Color(0xFFFFFFFF),
    mint: Color(0xFF2FD3A4),
    orange: Color(0xFFFFAE63),
    pink: Color(0xFFFF8DA1),
    purple: Color(0xFFA08CFF),
    sky: Color(0xFF4FC3F7),
    textPrimary: Color(0xFF171A23),
    textSecondary: Color(0xFF6B7385),
    textTertiary: Color(0xFF939BAD),
    success: Color(0xFF2ECC71),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF5A5F),
    border: Color(0xFFE9ECF5),
  );

  static const AppColors dark = AppColors(
    isDark: true,
    bgTop: Color(0xFF0A0D15),
    bgMid: Color(0xFF0D111A),
    bgBottom: Color(0xFF121621),
    surface: Color(0xFF171B26),
    surfaceAlt: Color(0xFF1E2331),
    surfaceSunken: Color(0xFF232838),
    primary: Color(0xFF5A8BFF),
    primaryDeep: Color(0xFF3F6BFF),
    onPrimary: Color(0xFFFFFFFF),
    mint: Color(0xFF34D8A8),
    orange: Color(0xFFFFB673),
    pink: Color(0xFFFF9AAE),
    purple: Color(0xFFAB98FF),
    sky: Color(0xFF5FCBF8),
    textPrimary: Color(0xFFF2F4F9),
    textSecondary: Color(0xFF9AA2B2),
    textTertiary: Color(0xFF7C8494),
    success: Color(0xFF34D399),
    warning: Color(0xFFFFB020),
    danger: Color(0xFFFF6B6F),
    border: Color(0xFF262C3A),
  );

  static AppColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  List<BoxShadow> get cardShadow => isDark
      ? const [
          BoxShadow(color: Color(0x66000000), blurRadius: 28, offset: Offset(0, 12)),
          BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
        ]
      : const [
          BoxShadow(color: Color(0x121B2B55), blurRadius: 30, offset: Offset(0, 12)),
          BoxShadow(color: Color(0x0A1B2B55), blurRadius: 6, offset: Offset(0, 2)),
        ];

  List<BoxShadow> get navShadow => isDark
      ? const [
          BoxShadow(color: Color(0x99000000), blurRadius: 30, offset: Offset(0, 14)),
        ]
      : const [
          BoxShadow(color: Color(0x1A1B2B55), blurRadius: 34, offset: Offset(0, 16)),
          BoxShadow(color: Color(0x0D1B2B55), blurRadius: 8, offset: Offset(0, 2)),
        ];

  LinearGradient get background => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [bgTop, bgMid, bgBottom],
        stops: const [0.0, 0.42, 1.0],
      );
}

class AppRadii {
  static const double card = 26;
  static const double cardSmall = 20;
  static const double tile = 18;
  static const double chip = 14;
  static const double field = 18;
  static const double nav = 30;
}

class AppSpacing {
  static const double page = 20;
  static const double gap = 16;
}

class AppText {
  static TextTheme textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: TextStyle(fontSize: 32, height: 1.12, fontWeight: FontWeight.w700, letterSpacing: -0.9, color: primary),
      displayMedium: TextStyle(fontSize: 28, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -0.7, color: primary),
      headlineMedium: TextStyle(fontSize: 23, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: primary),
      headlineSmall: TextStyle(fontSize: 20, height: 1.25, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: primary),
      titleLarge: TextStyle(fontSize: 18, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: primary),
      titleMedium: TextStyle(fontSize: 16.5, height: 1.3, fontWeight: FontWeight.w600, color: primary),
      titleSmall: TextStyle(fontSize: 15, height: 1.3, fontWeight: FontWeight.w600, color: primary),
      bodyLarge: TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w500, color: primary),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, fontWeight: FontWeight.w400, color: secondary),
      bodySmall: TextStyle(fontSize: 12.5, height: 1.4, fontWeight: FontWeight.w400, color: secondary),
      labelLarge: TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w600, color: primary),
      labelMedium: TextStyle(fontSize: 12, height: 1.3, fontWeight: FontWeight.w500, color: secondary),
      labelSmall: TextStyle(fontSize: 11, height: 1.3, fontWeight: FontWeight.w500, color: secondary),
    );
  }
}

class AppTheme {
  static ThemeData build(AppColors c) {
    final textTheme = AppText.textTheme(c.textPrimary, c.textSecondary);
    final scheme = ColorScheme(
      brightness: c.isDark ? Brightness.dark : Brightness.light,
      primary: c.primary,
      onPrimary: c.onPrimary,
      secondary: c.mint,
      onSecondary: Colors.white,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: c.isDark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: c.surface,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei UI', 'Noto Sans CJK SC', 'sans-serif'],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: c.textPrimary, size: 22),
        systemOverlayStyle: c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          textStyle: textTheme.titleSmall,
          elevation: 0,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          textStyle: textTheme.titleSmall,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.field), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.field), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.field),
          borderSide: BorderSide(color: c.primary.withValues(alpha: 0.55), width: 1.4),
        ),
        hintStyle: textTheme.bodyMedium!.copyWith(color: c.textTertiary),
        prefixIconColor: c.textTertiary,
        suffixIconColor: c.textTertiary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : c.surface),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.surfaceSunken),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        modalBackgroundColor: c.surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        showDragHandle: false,
        elevation: 0,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.isDark ? c.surfaceAlt : const Color(0xFF22273A),
        contentTextStyle: textTheme.bodyMedium!.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, linearTrackColor: c.surfaceSunken),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData light() => build(AppColors.light);

  static ThemeData dark() => build(AppColors.dark);
}

/// 让 `Theme` 之外也能方便拿到设计色板的小扩展。
extension AppContext on BuildContext {
  AppColors get colors => AppColors.of(this);
  TextTheme get texts => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
