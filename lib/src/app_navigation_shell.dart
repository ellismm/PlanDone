import 'package:flutter/material.dart';

import 'app_routes.dart';

class AppPrimaryScaffold extends StatelessWidget {
  const AppPrimaryScaffold({
    super.key,
    required this.activeRoute,
    required this.title,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String activeRoute;
  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final normalizedRoute = AppRoutes.normalizePrimary(activeRoute);
    final selectedIndex = _primaryDestinations.indexWhere(
      (destination) => destination.route == normalizedRoute,
    );
    final safeIndex = selectedIndex >= 0 ? selectedIndex : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 960;
        return Scaffold(
          appBar: AppBar(
            title: Text(title),
            actions: actions,
          ),
          floatingActionButton: floatingActionButton,
          body: useRail
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: safeIndex,
                      onDestinationSelected: (index) =>
                          _onSelectDestination(context, index),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final destination in _primaryDestinations)
                          NavigationRailDestination(
                            icon: Icon(destination.icon),
                            selectedIcon: Icon(destination.selectedIcon),
                            label: Text(destination.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: useRail
              ? null
              : NavigationBar(
                  selectedIndex: safeIndex,
                  onDestinationSelected: (index) =>
                      _onSelectDestination(context, index),
                  destinations: [
                    for (final destination in _primaryDestinations)
                      NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: destination.label,
                      ),
                  ],
                ),
        );
      },
    );
  }

  void _onSelectDestination(BuildContext context, int index) {
    final targetRoute = _primaryDestinations[index].route;
    if (AppRoutes.normalizePrimary(activeRoute) == targetRoute) {
      return;
    }
    Navigator.of(context).pushReplacementNamed(targetRoute);
  }
}

class _PrimaryDestination {
  const _PrimaryDestination({
    required this.route,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String route;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _primaryDestinations = [
  _PrimaryDestination(
    route: AppRoutes.workspace,
    label: 'Workspace',
    icon: Icons.dashboard_outlined,
    selectedIcon: Icons.dashboard,
  ),
  _PrimaryDestination(
    route: AppRoutes.boardConfiguration,
    label: 'Configuration',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
  _PrimaryDestination(
    route: AppRoutes.planning,
    label: 'Planning',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
  ),
];
