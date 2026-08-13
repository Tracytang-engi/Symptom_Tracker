import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'models/pain_event.dart';
import 'models/user_settings.dart';
import 'providers/ble_provider.dart';
import 'providers/events_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/timeline_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/stats_screen.dart';
import 'screens/sos_screen.dart';
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
import 'widgets/tag_selector.dart';

final _rootNavKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _rootNavKey,
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => _ShellScaffold(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
        GoRoute(
          path: '/timeline',
          builder: (_, __) => const TimelineScreen(),
          routes: [
            GoRoute(
              path: ':id',
              parentNavigatorKey: _rootNavKey,
              builder: (_, state) {
                final event = state.extra as PainEvent;
                return EventDetailScreen(event: event);
              },
            ),
          ],
        ),
        GoRoute(path: '/sos', builder: (_, __) => const SosScreen()),
        GoRoute(path: '/stats', builder: (_, __) => const StatsScreen()),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
          routes: [
            GoRoute(path: 'vibration', parentNavigatorKey: _rootNavKey, builder: (_, __) => const VibrationSettingsScreen()),
            GoRoute(path: 'calibration', parentNavigatorKey: _rootNavKey, builder: (_, __) => const CalibrationScreen()),
            GoRoute(path: 'labels', parentNavigatorKey: _rootNavKey, builder: (_, __) => const LabelSettingsScreen()),
            GoRoute(path: 'appearance', parentNavigatorKey: _rootNavKey, builder: (_, __) => const AppearanceSettingsScreen()),
            GoRoute(path: 'recording', parentNavigatorKey: _rootNavKey, builder: (_, __) => const RecordingSettingsScreen()),
            GoRoute(path: 'post-event', parentNavigatorKey: _rootNavKey, builder: (_, __) => const PostEventSettingsScreen()),
            GoRoute(path: 'ble', parentNavigatorKey: _rootNavKey, builder: (_, __) => const BleSettingsScreen()),
            GoRoute(path: 'symptom-profile', parentNavigatorKey: _rootNavKey, builder: (_, __) => const SymptomProfileScreen()),
            GoRoute(path: 'accessibility', parentNavigatorKey: _rootNavKey, builder: (_, __) => const AccessibilityScreen()),
            GoRoute(path: 'reminders', parentNavigatorKey: _rootNavKey, builder: (_, __) => const RemindersScreen()),
            GoRoute(path: 'privacy', parentNavigatorKey: _rootNavKey, builder: (_, __) => const PrivacyScreen()),
            GoRoute(path: 'guardian', parentNavigatorKey: _rootNavKey, builder: (_, __) => const GuardianModeScreen()),
          ],
        ),
      ],
    ),
  ],
);

class _ShellScaffold extends ConsumerStatefulWidget {
  final Widget child;
  const _ShellScaffold({required this.child});

  @override
  ConsumerState<_ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends ConsumerState<_ShellScaffold> {
  static const _routesNormal = ['/', '/timeline', '/stats', '/settings'];
  // Accessible：去掉 SOS 栏，仅 Home / Timeline（退出模式靠首页按钮）
  static const _routesAccessible = ['/', '/timeline'];

  @override
  void initState() {
    super.initState();
    ref.read(bleEventListenerProvider);
  }

  /// 根据当前路由同步底部栏高亮（含从 Home 点 today episodes 跳转 Timeline）
  int _indexForLocation(String path, List<String> routes) {
    for (var i = 0; i < routes.length; i++) {
      final r = routes[i];
      if (r == '/') {
        if (path == '/') return i;
      } else if (path == r || path.startsWith('$r/')) {
        return i;
      }
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final accessible = ref.watch(userSettingsProvider).accessibleMode;
    final routes = accessible ? _routesAccessible : _routesNormal;
    final location = GoRouterState.of(context).uri.path;
    final safeIndex = _indexForLocation(location, routes);

    // 切换模式时若当前页不在新导航里，回到 Home
    ref.listen<bool>(
      userSettingsProvider.select((s) => s.accessibleMode),
      (prev, next) {
        if (prev == next) return;
        final loc = GoRouterState.of(context).uri.path;
        final allowed = next ? _routesAccessible : _routesNormal;
        if (!allowed.contains(loc) && !loc.startsWith('/timeline/')) {
          context.go('/');
        }
      },
    );

    ref.listen<SosAlert?>(lastSosAlertProvider, (prev, next) {
      if (next == null) return;
      final nav = _rootNavKey.currentContext;
      if (nav == null) return;
      showDialog(
        context: nav,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.sos, color: Colors.red, size: 56),
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

    // 发作结束后弹标签（PostEvent：promptTags / promptIfAbnormal）
    ref.listen<PainEvent?>(pendingTagPromptProvider, (prev, next) async {
      if (next == null) return;
      final nav = _rootNavKey.currentContext;
      if (nav == null) return;

      final result = await TagSelector.show(nav, next.tags);
      // 先清掉 pending，避免重复弹
      ref.read(pendingTagPromptProvider.notifier).state = null;

      if (result != null) {
        await ref.read(eventsProvider.notifier).updateEvent(
              next.copyWith(tags: result),
            );
      }
    });

    // 设备语音录完提示（会自动 BLE 下载并挂到对应发作）
    ref.listen<DeviceRecDone?>(lastDeviceRecDoneProvider, (prev, next) {
      if (next == null) return;
      final nav = _rootNavKey.currentContext;
      if (nav == null) return;
      final empty = next.sizeBytes <= 44 || next.durationMs <= 0;
      ScaffoldMessenger.of(nav).showSnackBar(
        SnackBar(
          content: Text(
            empty
                ? 'Device recording failed (empty file). '
                    'Clear device storage if SPIFFS is full.'
                : 'Device voice: ${next.path} '
                    '(${(next.durationMs / 1000).toStringAsFixed(1)}s) — downloading…',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    });

    return Scaffold(//Scaffold = 框架，包含头部、底部、内容区
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeIndex,
        onDestinationSelected: (i) => context.go(routes[i]),
        destinations: accessible
            ? [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined, color: AppColors.navHome.withOpacity(0.7), size: 30),
                  selectedIcon: const Icon(Icons.home, color: AppColors.navHome, size: 32),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.timeline_outlined, color: AppColors.navTimeline.withOpacity(0.7), size: 30),
                  selectedIcon: const Icon(Icons.timeline, color: AppColors.navTimeline, size: 32),
                  label: 'Timeline',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined, color: AppColors.navHome),
                  selectedIcon: Icon(Icons.home, color: AppColors.navHome),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.timeline_outlined, color: AppColors.navTimeline),
                  selectedIcon: Icon(Icons.timeline, color: AppColors.navTimeline),
                  label: 'Timeline',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined, color: AppColors.navStats),
                  selectedIcon: Icon(Icons.bar_chart, color: AppColors.navStats),
                  label: 'Stats',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined, color: AppColors.navSettings),
                  selectedIcon: Icon(Icons.settings, color: AppColors.navSettings),
                  label: 'Settings',
                ),
              ],
      ),
    );
  }
}

class SymptomTrackerApp extends ConsumerWidget {
  const SymptomTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(userSettingsProvider);

    ThemeMode themeMode = switch (settings.darkMode) {
      DarkModeOption.system => ThemeMode.system,
      DarkModeOption.light => ThemeMode.light,
      DarkModeOption.dark => ThemeMode.dark,
    };

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(settings.fontSize.scale),
      ),
      child: MaterialApp.router(
        title: 'Symptom Tracker',
        theme: AppTheme.light(
          settings.themeVariant,
          accessibleMode: settings.accessibleMode,
          largeButtons: settings.largeButtons,
        ),
        darkTheme: AppTheme.dark(
          settings.themeVariant,
          accessibleMode: settings.accessibleMode,
          largeButtons: settings.largeButtons,
        ),
        themeMode: themeMode,
        routerConfig: _router,
      ),
    );
  }
}
