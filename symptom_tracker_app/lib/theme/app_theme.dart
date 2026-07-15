import 'package:flutter/material.dart';  // Flutter UI 框架核心库

// ─── 品牌颜色常量 ─────────────────────────────────────────────────────────────

class AppColors {                          // 专门存颜色的工具类，所有成员都是 static const
  // Teal 绿（偏蓝绿）
  static const tealPrimary = Color(0xFF66BB6A);  // Color(0xFF...) = 用 ARGB 十六进制指定颜色
  static const tealDark    = Color(0xFF388E3C);
  static const tealLight   = Color(0xFFA5D6A7);

  // Sage 绿（偏灰绿）
  static const sagePrimary = Color(0xFF87A878);
  static const sageDark    = Color(0xFF5A7A4A);
  static const sageLight   = Color(0xFFB8CCB0);

  // 通用色
  static const backgroundLight   = Color(0xFFF1F8E9);  // 浅色背景
  static const backgroundDark    = Color(0xFF1B2B1D);  // 深色背景
  static const cardLight         = Colors.white;        // 卡片背景
  static const cardDark          = Color(0xFF253427);
  static const textPrimaryLight  = Color(0xFF1B5E20);
  static const textPrimaryDark   = Color(0xFFD4EDDA);
  static const sosRed            = Color(0xFFEF5350);
  static const chartGradientStart = Color(0xFFA5D6A7);
  static const chartGradientEnd   = Color(0xFF2E7D32);
}

// ─── 主题变体枚举 ─────────────────────────────────────────────────────────────

enum AppThemeVariant { teal, sage }        // 用户可以在设置里切换这两种绿色主题

// ─── 字体大小枚举 ─────────────────────────────────────────────────────────────

enum AppFontSize { small, standard, large, xlarge }

extension AppFontSizeExt on AppFontSize {  // extension = 给 AppFontSize 枚举附加方法
  double get scale {                       // 返回对应的文字缩放比例
    switch (this) {
      case AppFontSize.small:    return 0.85;
      case AppFontSize.standard: return 1.0;
      case AppFontSize.large:    return 1.2;
      case AppFontSize.xlarge:   return 1.5;
    }
  }

  String get label {                       // 返回用户可读的名称
    switch (this) {
      case AppFontSize.small:    return 'Small';
      case AppFontSize.standard: return 'Standard';
      case AppFontSize.large:    return 'Large';
      case AppFontSize.xlarge:   return 'Extra Large';
    }
  }
}

// ─── 主题构建器 ───────────────────────────────────────────────────────────────

class AppTheme {
  // 浅色主题：根据变体选不同主色调
  static ThemeData light(AppThemeVariant variant) {    // static = 不需要实例直接调用
    final primary = variant == AppThemeVariant.teal    // 三元表达式：条件 ? 真值 : 假值
        ? AppColors.tealPrimary
        : AppColors.sagePrimary;
    final dark = variant == AppThemeVariant.teal
        ? AppColors.tealDark
        : AppColors.sageDark;

    final colorScheme = ColorScheme.fromSeed(         // ColorScheme = Flutter 定义全局颜色方案的类
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,                        // onPrimary = 主色上面的文字颜色
      primaryContainer: AppColors.backgroundLight,
      secondary: dark,
      surface: AppColors.cardLight,
      onSurface: AppColors.textPrimaryLight,
    );

    return _buildTheme(colorScheme, primary, dark, Brightness.light);  // 调用私有方法
  }

  // 深色主题
  static ThemeData dark(AppThemeVariant variant) {
    final primary = variant == AppThemeVariant.teal
        ? AppColors.tealLight      // 深色模式下用更亮的颜色提高对比度
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

    return _buildTheme(colorScheme, primary, dark, Brightness.dark);
  }

  // 私有方法（_ 开头 = 只能在本文件内使用）：组装完整 ThemeData
  static ThemeData _buildTheme(
    ColorScheme colorScheme,
    Color primary,
    Color dark,
    Brightness brightness,
  ) {
    final isDark = brightness == Brightness.dark;  // 判断是否深色模式
    return ThemeData(
      useMaterial3: true,                          // 使用 Material 3 设计规范
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,  // 页面底层背景色
      appBarTheme: AppBarTheme(                    // 导航栏全局样式
        backgroundColor: isDark ? AppColors.cardDark : primary,
        foregroundColor: isDark ? AppColors.textPrimaryDark : Colors.white,
        elevation: 0,                              // elevation = 阴影高度，0 = 无阴影
        centerTitle: false,
      ),
      cardTheme: CardThemeData(                    // 所有 Card 的默认样式
        color: isDark ? AppColors.cardDark : AppColors.cardLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), // 圆角半径 16px
          side: BorderSide(
            color: primary.withOpacity(0.2),       // .withOpacity() = 给颜色加透明度（0.0~1.0）
            width: 1,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(    // 填充按钮全局样式
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),  // 按钮内边距
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(         // WidgetStateProperty = 根据状态返回不同颜色
          (s) => s.contains(WidgetState.selected) ? primary : Colors.grey,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? primary.withOpacity(0.4) : null,
        ),
      ),
      sliderTheme: SliderThemeData(activeTrackColor: primary, thumbColor: dark),  // 滑块颜色
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(space: 1, thickness: 0.5),  // 分割线厚度
      inputDecorationTheme: InputDecorationTheme(  // 输入框全局样式
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),  // 聚焦时加粗边框
        ),
      ),
      chipTheme: ChipThemeData(                    // 标签芯片全局样式
        selectedColor: primary.withOpacity(0.2),
        labelStyle: TextStyle(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        side: BorderSide(color: primary.withOpacity(0.3)),
      ),
    );
  }
}
