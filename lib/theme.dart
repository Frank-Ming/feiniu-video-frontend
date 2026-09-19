import 'package:flutter/material.dart';

/// 飞牛短视频主题 - 高级暗色配色
///
/// 设计要点：
/// - 主色：温暖的暗红橙 (#E94560) 而非鲜艳粉
/// - 背景：接近纯黑 (#0B0B0F) + 微妙的紫灰渐变
/// - 强调色：金色 (#F5B955) 用于关键交互
/// - 文字层次：白 / 灰白 / 灰 三档
class AppColors {
  static const bg = Color(0xFF0B0B0F);
  static const bgElev = Color(0xFF15151C);
  static const bgCard = Color(0xFF1E1E28);
  static const primary = Color(0xFFE94560);          // 主色
  static const primaryDark = Color(0xFFB7314A);
  static const accent = Color(0xFFF5B955);           // 金色强调
  static const textPrimary = Color(0xFFFAFAFA);
  static const textSecondary = Color(0xFFB8B8C7);
  static const textTertiary = Color(0xFF75758A);
  static const divider = Color(0xFF2A2A35);
  static const success = Color(0xFF4ADE80);
  static const danger = Color(0xFFF87171);

  // 渐变
  static const gradientBrand = LinearGradient(
    colors: [Color(0xFFE94560), Color(0xFFF5B955)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const gradientScaffold = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0F0F18), Color(0xFF050507)],
  );
  static const gradientCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E1E28), Color(0xFF15151C)],
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.bgElev,
      onPrimary: Colors.white,
      onSecondary: Colors.black,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    ).copyWith(
      headlineLarge: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.5),
      titleLarge: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      bodyMedium: const TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary),
      bodySmall: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: AppColors.textTertiary),
      labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      iconTheme: IconThemeData(color: AppColors.textPrimary),
      titleTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
    ),
    cardTheme: const CardThemeData(color: AppColors.bgCard, elevation: 0),
    dividerColor: AppColors.divider,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bgElev,
      hintStyle: const TextStyle(color: AppColors.textTertiary),
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.2),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.bgCard,
      contentTextStyle: TextStyle(color: AppColors.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.bgElev,
      labelStyle: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
      side: const BorderSide(color: AppColors.divider),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
  );
}
