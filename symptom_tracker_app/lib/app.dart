import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';    // go_router = 声明式路由库
import 'models/pain_event.dart';
import 'models/user_settings.dart';
import 'providers/ble_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/timeline_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/vibration_settings_screen.dart';
import 'screens/settings/calibration_screen.dart';
import 'screens/settings/label_settings_screen.dart';
import 'screens/settings/appearance_settings_screen.dart';
import 'screens/settings/recording_settings_screen.dart';
import 'screens/settings/post_event_settings_screen.dart';
import 'screens/settings/ble_settings_screen.dart';
import 'screens/settings/symptom_profile_screen.dart';
import 'screens/settings/accessibility_screen.dart';
import 'theme/app_theme.dart';

// GlobalKey = 可以在全局访问某个 Widget 的状态（这里用于控制导航栈）
final _rootNavKey = GlobalKey<NavigatorState>();

// GoRouter 路由表（声明式：把路径映射到页面）
final _router = GoRouter(
  navigatorKey: _rootNavKey,
  initialLocation: '/',       // 启动时显示的页面路径
  routes: [
    // ShellRoute = 带持久底部导航栏的壳子，包裹所有主页面
    ShellRoute(
      builder: (context, state, child) => _ShellScaffold(child: child),  // child = 当前激活的子页面
      routes: [
        GoRoute(path: '/',         builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/timeline',
          builder: (_, __) => const TimelineScreen(),
          routes: [
            GoRoute(
              path: ':id',                             // :id = 路径参数（动态段）
              parentNavigatorKey: _rootNavKey,         // 使用根导航栈（全屏跳转，无底部栏）
              builder: (_, state) {
                final event = state.extra as PainEvent;  // state.extra = 路由跳转时附带的对象
                return EventDetailScreen(event: event);
              },
            ),
          ],
        ),
        GoRoute(path: '/stats',    builder: (_, __) => const StatsScreen()),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
          routes: [  // 子路由：设置的各个子页面
            GoRoute(path: 'vibration',       parentNavigatorKey: _rootNavKey, builder: (_, __) => const VibrationSettingsScreen()),
            GoRoute(path: 'calibration',     parentNavigatorKey: _rootNavKey, builder: (_, __) => const CalibrationScreen()),
            GoRoute(path: 'labels',          parentNavigatorKey: _rootNavKey, builder: (_, __) => const LabelSettingsScreen()),
            GoRoute(path: 'appearance',      parentNavigatorKey: _rootNavKey, builder: (_, __) => const AppearanceSettingsScreen()),
            GoRoute(path: 'recording',       parentNavigatorKey: _rootNavKey, builder: (_, __) => const RecordingSettingsScreen()),
            GoRoute(path: 'post-event',      parentNavigatorKey: _rootNavKey, builder: (_, __) => const PostEventSettingsScreen()),
            GoRoute(path: 'ble',             parentNavigatorKey: _rootNavKey, builder: (_, __) => const BleSettingsScreen()),
            GoRoute(path: 'symptom-profile', parentNavigatorKey: _rootNavKey, builder: (_, __) => const SymptomProfileScreen()),
            GoRoute(path: 'accessibility',   parentNavigatorKey: _rootNavKey, builder: (_, __) => const AccessibilityScreen()),
            GoRoute(path: 'reminders',       parentNavigatorKey: _rootNavKey, builder: (_, __) => const RemindersScreen()),
            GoRoute(path: 'privacy',         parentNavigatorKey: _rootNavKey, builder: (_, __) => const PrivacyScreen()),
            GoRoute(path: 'guardian',        parentNavigatorKey: _rootNavKey, builder: (_, __) => const GuardianModeScreen()),
          ],
        ),
      ],
    ),
  ],
);

// ─── 带底部导航栏的"壳子"Widget ──────────────────────────────────────────────

// ConsumerStatefulWidget = 有状态 + 可以访问 Riverpod 的 Widget
class _ShellScaffold extends ConsumerStatefulWidget {
  final Widget child;
  const _ShellScaffold({required this.child});

  @override
  ConsumerState<_ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<_ShellScaffold> {
  int _index = 0;  // 当前选中的底部导航项

  static const _routes           = ['/', '/timeline', '/stats', '/settings'];
  static const _routesSimplified = ['/', '/timeline', '/settings'];  // 简化模式少一个 Stats

  @override
  void initState() {
    super.initState();
    // 在壳层激活 BLE 监听，保证任意页签下硬件 SOS / 按压事件都能收到
    ref.read(bleEventListenerProvider);
  }

  @override
  Widget build(BuildContext context) {
    final simplified = ref.watch(userSettingsProvider).simplifiedUI;  // ref.watch = 监听设置变化
    final routes = simplified ? _routesSimplified : _routes;
    final safeIndex = _index.clamp(0, routes.length - 1);  // .clamp = 防止 index 越界

    // 硬件或 App 内触发 SOS 时弹窗（任意主页签都能看到）
    ref.listen<SosAlert?>(lastSosAlertProvider, (prev, next) {
      if (next == null) return;
      final nav = _rootNavKey.currentContext;
      if (nav == null) return;
      showDialog(
        context: nav,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.sos, color: Colors.red, size: 48),
          title: const Text('SOS Triggered'),
          content: Text(
            next.location != null
                ? '${next.fromDevice ? "Device button" : "App"} alert sent.\nLocation: ${next.location}'
                : '${next.fromDevice ? "Device button" : "App"} alert sent.\nLocation unavailable.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    });

    return Scaffold(
      body: widget.child,  // widget.child = 访问父 Widget 传入的 child（ConsumerState 专属写法）
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) {
          setState(() => _index = i);  // setState = 通知 Flutter 重建 UI
          context.go(routes[i]);       // context.go() = GoRouter 跳转（替换当前路由，无返回按钮）
        },
        destinations: simplified
            ? const [
                NavigationDestination(icon: Icon(Icons.home_outlined),     selectedIcon: Icon(Icons.home),      label: 'Home'),
                NavigationDestination(icon: Icon(Icons.timeline_outlined),  selectedIcon: Icon(Icons.timeline),  label: 'Timeline'),
                NavigationDestination(icon: Icon(Icons.settings_outlined),  selectedIcon: Icon(Icons.settings),  label: 'Settings'),
              ]
            : const [
                NavigationDestination(icon: Icon(Icons.home_outlined),      selectedIcon: Icon(Icons.home),       label: 'Home'),
                NavigationDestination(icon: Icon(Icons.timeline_outlined),   selectedIcon: Icon(Icons.timeline),   label: 'Timeline'),
                NavigationDestination(icon: Icon(Icons.bar_chart_outlined),  selectedIcon: Icon(Icons.bar_chart),  label: 'Stats'),
                NavigationDestination(icon: Icon(Icons.settings_outlined),   selectedIcon: Icon(Icons.settings),   label: 'Settings'),
              ],
      ),
    );
  }
}

// ─── App 根 Widget ────────────────────────────────────────────────────────────

class SymptomTrackerApp extends ConsumerWidget {  // ConsumerWidget = 可以访问 Riverpod Provider 的无状态 Widget
  const SymptomTrackerApp({super.key});           // super.key = 把 key 传给父类（Widget 标识用）

  @override
  Widget build(BuildContext context, WidgetRef ref) {  // WidgetRef = Riverpod 的 ref，在 ConsumerWidget 里替代 ref.read/watch
    final settings = ref.watch(userSettingsProvider); // 监听设置变化，变化时重建整个 App

    // switch 表达式：根据枚举值映射到 ThemeMode（Dart 3.0 新语法）
    ThemeMode themeMode = switch (settings.darkMode) {
      DarkModeOption.system => ThemeMode.system,
      DarkModeOption.light  => ThemeMode.light,
      DarkModeOption.dark   => ThemeMode.dark,
    };

    return MediaQuery(
      // 覆盖 MediaQuery 的 textScaler，让字体缩放生效于整个 App
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(settings.fontSize.scale),
      ),
      child: MaterialApp.router(          // MaterialApp.router = 使用 GoRouter 的 Material App 变体
        title: 'Symptom Tracker',
        theme: AppTheme.light(settings.themeVariant),
        darkTheme: AppTheme.dark(settings.themeVariant),
        themeMode: themeMode,
        routerConfig: _router,            // 把路由表交给 MaterialApp 管理
      ),
    );
  }
}
