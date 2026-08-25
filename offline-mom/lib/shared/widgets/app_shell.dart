import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_paths.dart';

/// Persistent bottom-navigation chrome for the four top-level destinations
/// (Home, History, Search, Settings). Wrapped around the four routes via a
/// go_router `ShellRoute` so the bar survives navigation between them.
///
/// **Product validation phase (real-device release prep):** the docked
/// center record-shortcut FAB that used to live here was removed - it was
/// the one persistent, center-dominant recording affordance visible on
/// every single screen in the app, and was judged to be actively working
/// against the product's own broader positioning ("a private offline AI
/// workspace," not "a voice recorder with extra features"). Recording
/// remains fully reachable, unchanged, via Home's own "Record meeting"
/// Quick Action tile (`home_screen.dart`) - nothing about the recording
/// *feature* was removed, only its one non-contextual, always-visible
/// shortcut. The 4 nav tabs now spread evenly across the full bar width
/// instead of leaving a center gap/notch for a FAB that no longer exists.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _tabs = [
    (path: RoutePaths.home, icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
    (path: RoutePaths.history, icon: Icons.history_rounded, selectedIcon: Icons.history_rounded, label: 'History'),
    (path: RoutePaths.search, icon: Icons.search_outlined, selectedIcon: Icons.search_rounded, label: 'Search'),
    (path: RoutePaths.settings, icon: Icons.settings_outlined, selectedIcon: Icons.settings_rounded, label: 'Settings'),
  ];

  int _indexForLocation(String location) {
    final index = _tabs.indexWhere((t) => location.startsWith(t.path));
    return index == -1 ? 0 : index;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final currentIndex = _indexForLocation(location);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: child,
      bottomNavigationBar: BottomAppBar(
        padding: EdgeInsets.zero,
        height: 68,
        color: scheme.surfaceContainerLow,
        elevation: 0,
        child: Row(
          children: [
            for (final tab in _tabs)
              _NavTab(
                tab: tab,
                isSelected: _tabs.indexOf(tab) == currentIndex,
                onTap: () => context.go(tab.path),
              ),
          ],
        ),
      ),
    );
  }
}

typedef _Tab = ({
  String path,
  IconData icon,
  IconData selectedIcon,
  String label,
});

class _NavTab extends StatelessWidget {
  const _NavTab({required this.tab, required this.isSelected, required this.onTap});

  final _Tab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isSelected ? scheme.primary : scheme.onSurfaceVariant;

    return Expanded(
      child: Semantics(
        selected: isSelected,
        button: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(isSelected ? tab.selectedIcon : tab.icon, color: color),
              const SizedBox(height: 2),
              Text(
                tab.label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

