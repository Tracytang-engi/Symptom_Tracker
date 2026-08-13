import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../theme/app_theme.dart';

/// 备用底部导航（主壳在 app.dart）
class AppBottomNav extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accessible = ref.watch(userSettingsProvider).accessibleMode;

    final destinations = accessible
        ? const [
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
          ];

    return NavigationBar(
      selectedIndex: currentIndex.clamp(0, destinations.length - 1),
      onDestinationSelected: onTap,
      destinations: destinations,
    );
  }
}
