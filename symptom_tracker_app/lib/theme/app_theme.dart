import 'package:flutter/material.dart';

// ─── 品牌颜色常量 ─────────────────────────────────────────────────────────────

class AppColors {
  static const tealPrimary = Color(0xFF66BB6A);
  static const tealDark    = Color(0xFF388E3C);
  static const tealLight   = Color(0xFFA5D6A7);

  static const sagePrimary = Color(0xFF87A878);
  static const sageDark    = Color(0xFF5A7A4A);
  static const sageLight   = Color(0xFFB8CCB0);

  static const backgroundLight   = Color(0xFFF1F8E9);
  static const backgroundDark    = Color(0xFF1B2B1D);
  static const cardLight         = Colors.white;
  static const cardDark          = Color(0xFF253427);
  static const textPrimaryLight  = Color(0xFF1B5E20);
  static const textPrimaryDark   = Color(0xFFD4EDDA);
  static const sosRed            = Color(0xFFEF5350);
  static const chartGradientStart = Color(0xFFA5D6A7);
  static const chartGradientEnd   = Color(0xFF2E7D32);

  // Accessible 高对比
  static const hcPrimaryLight    = Color(0xFF1B5E20);
  static const hcOnPrimaryLight  = Colors.white;
  static const hcBgLight         = Colors.white;
  static const hcTextLight       = Color(0xFF0D1F0E);
  static const hcPrimaryDark     = Color(0xFF81C784);
  static const hcBgDark          = Color(0xFF000000);
  static const hcTextDark        = Color(0xFFE8F5E9);

  // 导航多彩图标
  static const navHome     = Color(0xFF2E7D32);
  static const navTimeline = Color(0xFF1565C0);
  static const navSos      = Color(0xFFEF5350);
  static const navStats    = Color(0xFF6A1B9A);
  static const navSettings = Color(0xFF546E7A);
}

enum AppThemeVariant { teal, sage }

enum AppFontSize { small, standard, large, xlarge }

extension AppFontSizeExt on AppFontSize {
  double get scale {
    switch (this) {
      case AppFontSize.small:    return 0.85;
      case AppFontSize.standard: return 1.0;
      case AppFontSize.large:    return 1.2;
      case AppFontSize.xlarge:   return 1.5;
    }
  }

  String get label {
    switch (this) {
      case AppFontSize.small:    return 'Small';
      case AppFontSize.standard: return 'Standard';
      case AppFontSize.large:    return 'Large';
      case AppFontSize.xlarge:   return 'Extra Large';
    }
  }
}

class AppTheme {
  static ThemeData light(
    AppThemeVariant variant, {
    bool accessibleMode = false,
    bool largeButtons = false,
  }) {
    if (accessibleMode) {
      return _highContrastLight(largeButtons: true);
    }
    final primary = variant == AppThemeVariant.teal
        ? AppColors.tealPrimary
        : AppColors.sagePrimary;
    final dark = variant == AppThemeVariant.teal
        ? AppColors.tealDark
        : AppColors.sageDark;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: AppColors.backgroundLight,
      secondary: dark,
      surface: AppColors.cardLight,
      onSurface: AppColors.textPrimaryLight,
    );

    return _buildTheme(
      colorScheme,
      primary,
      dark,
      Brightness.light,
      largeButtons: largeButtons,
      accessibleMode: false,
    );
  }

  static ThemeData dark(
    AppThemeVariant variant, {
    bool accessibleMode = false,
    bool largeButtons = false,
  }) {
    if (accessibleMode) {
      return _highContrastDark(largeButtons: true);
    }
    final primary = variant == AppThemeVariant.teal
        ? AppColors.tealLight
        : AppColors.sageLight;
    final dark = variant == AppThemeVariant.teal
        ? AppColors.tealPrimary
        : AppColors.sagePrimary;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
      primary: primary,
      onPrimary: AppColors.backgroundDark,
      surface: AppColors.cardDark,
      onSurface: AppColors.textPrimaryDark,
    );

    return _buildTheme(
      colorScheme,
      primary,
      dark,
      Brightness.dark,
      largeButtons: largeButtons,
      accessibleMode: false,
    );
  }

  static ThemeData _highContrastLight({required bool largeButtons}) {
    final primary = AppColors.hcPrimaryLight;
    final colorScheme = ColorScheme.light(
      primary: primary,
      onPrimary: AppColors.hcOnPrimaryLight,
      secondary: AppColors.tealDark,
      surface: AppColors.hcBgLight,
      onSurface: AppColors.hcTextLight,
    );
    return _buildTheme(
      colorScheme,
      primary,
      AppColors.tealDark,
      Brightness.light,
      largeButtons: largeButtons,
      accessibleMode: true,
      scaffoldBg: AppColors.hcBgLight,
    );
  }

  static ThemeData _highContrastDark({required bool largeButtons}) {
    final primary = AppColors.hcPrimaryDark;
    final colorScheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.black,
      secondary: AppColors.tealLight,
      surface: const Color(0xFF121212),
      onSurface: AppColors.hcTextDark,
    );
    return _buildTheme(
      colorScheme,
      primary,
      AppColors.tealLight,
      Brightness.dark,
      largeButtons: largeButtons,
      accessibleMode: true,
      scaffoldBg: AppColors.hcBgDark,
    );
  }

  static ThemeData _buildTheme(
    ColorScheme colorScheme,
    Color primary,
    Color dark,
    Brightness brightness, {
    required bool largeButtons,
    required bool accessibleMode,
    Color? scaffoldBg,
  }) {
    final isDark = brightness == Brightness.dark;
    final btnHeight = accessibleMode ? 64.0 : (largeButtons ? 56.0 : 48.0);
    final btnPadV = accessibleMode ? 18.0 : (largeButtons ? 16.0 : 14.0);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: scaffoldBg ??
          (isDark ? AppColors.backgroundDark : AppColors.backgroundLight),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark
            ? (accessibleMode ? const Color(0xFF121212) : AppColors.cardDark)
            : primary,
        foregroundColor: isDark
            ? AppColors.textPrimaryDark
            : Colors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: accessibleMode ? 22 : 20,
          fontWeight: FontWeight.w600,
          color: isDark ? AppColors.textPrimaryDark : Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        elevation: 0,
        margin: EdgeInsets.symmetric(
          horizontal: accessibleMode ? 12 : 8,
          vertical: accessibleMode ? 10 : 6,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: primary.withOpacity(accessibleMode ? 0.45 : 0.2),
            width: accessibleMode ? 2 : 1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: colorScheme.onPrimary,
          minimumSize: Size.fromHeight(btnHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: btnPadV),
          textStyle: TextStyle(
            fontSize: accessibleMode ? 18 : 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size.fromHeight(btnHeight),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: EdgeInsets.symmetric(horizontal: 24, vertical: btnPadV),
          side: BorderSide(color: primary, width: accessibleMode ? 2.5 : 1.5),
          textStyle: TextStyle(
            fontSize: accessibleMode ? 18 : 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: accessibleMode ? 80 : 64,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: accessibleMode ? 14 : 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(size: accessibleMode ? 32 : 24, opticalSize: selected ? 1 : 1);
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary : Colors.grey,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary.withOpacity(0.4) : null,
        ),
      ),
      sliderTheme: SliderThemeData(activeTrackColor: primary, thumbColor: dark),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        minVerticalPadding: accessibleMode ? 16 : 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 0.5),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
      chipTheme: ChipThemeData(
        selectedColor: primary.withOpacity(0.2),
        labelStyle: TextStyle(
          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
          fontSize: accessibleMode ? 14 : 12,
        ),
        side: BorderSide(color: primary.withOpacity(0.3)),
      ),
    );
  }
}
