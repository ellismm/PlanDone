import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_routes.dart';
import 'core/branding/plan_done_branding.dart';
import 'core/help/app_help.dart';
import 'core/help/app_help_controller.dart';
import 'core/help/app_help_widgets.dart';

class AppPrimaryScaffold extends ConsumerWidget {
  const AppPrimaryScaffold({
    super.key,
    required this.activeRoute,
    required this.title,
    required this.body,
    required this.helpSurface,
    this.actions = const [],
    this.floatingActionButton,
    this.onActiveDestinationTap,
    this.workspaceIcon,
    this.workspaceSelectedIcon,
  });

  final String activeRoute;
  final String title;
  final Widget body;
  final AppHelpSurfaceId helpSurface;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final VoidCallback? onActiveDestinationTap;
  final IconData? workspaceIcon;
  final IconData? workspaceSelectedIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final normalizedRoute = AppRoutes.normalizePrimary(activeRoute);
    final selectedIndex = _primaryDestinations.indexWhere(
      (destination) => destination.route == normalizedRoute,
    );
    final safeIndex = selectedIndex >= 0 ? selectedIndex : 0;
    final helpModeEnabled = ref.watch(appHelpModeEnabledProvider);
    final showFloatingHelpButton = ref.watch(appHelpShowFloatingButtonProvider);

    final helpAction = IconButton(
      tooltip: helpModeEnabled ? 'Exit Help mode' : 'Help mode',
      onPressed: () => ref.read(appHelpControllerProvider).toggleHelpMode(),
      icon: Icon(
        helpModeEnabled ? Icons.help : Icons.help_outline,
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 960;
        final resolvedFloatingActionButton = _buildFloatingButtons(
          ref,
          showFloatingHelpButton: showFloatingHelpButton,
        );
        final resolvedBody = Stack(
          children: [
            body,
            const AppHelpPreferencesBridge(),
            AppHelpOverlay(surface: helpSurface),
          ],
        );
        return TapRegionSurface(
          child: Scaffold(
            appBar: AppBar(
              leadingWidth: 56,
              leading: const Padding(
                padding: EdgeInsetsDirectional.only(start: 16),
                child: Center(child: PlanDoneBrandMark(size: 28)),
              ),
              title: Text(title),
              actions: [...actions, helpAction],
            ),
            floatingActionButton: resolvedFloatingActionButton,
            body: useRail
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: safeIndex,
                        onDestinationSelected: (index) =>
                            _onSelectDestination(context, index),
                        labelType: NavigationRailLabelType.all,
                        destinations: [
                          for (final destination in _resolvedDestinations)
                            NavigationRailDestination(
                              icon: Icon(destination.icon),
                              selectedIcon: Icon(destination.selectedIcon),
                              label: Text(destination.label),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: resolvedBody),
                    ],
                  )
                : resolvedBody,
            bottomNavigationBar: useRail
                ? null
                : NavigationBar(
                    selectedIndex: safeIndex,
                    onDestinationSelected: (index) =>
                        _onSelectDestination(context, index),
                    destinations: [
                      for (final destination in _resolvedDestinations)
                        NavigationDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: destination.label,
                        ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget? _buildFloatingButtons(
    WidgetRef ref, {
    required bool showFloatingHelpButton,
  }) {
    final enableHelpMode = ref.watch(appHelpModeEnabledProvider);
    final helpButton = showFloatingHelpButton
        ? FloatingActionButton.small(
            heroTag: 'floating-help-$activeRoute',
            tooltip: enableHelpMode ? 'Exit Help mode' : 'Help mode',
            onPressed: () =>
                ref.read(appHelpControllerProvider).toggleHelpMode(),
            child: Icon(enableHelpMode ? Icons.help : Icons.help_outline),
          )
        : null;

    if (helpButton == null) {
      return floatingActionButton;
    }
    if (floatingActionButton == null) {
      return helpButton;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        helpButton,
        const SizedBox(height: 12),
        floatingActionButton!,
      ],
    );
  }

  void _onSelectDestination(BuildContext context, int index) {
    final targetRoute = _resolvedDestinations[index].route;
    if (AppRoutes.normalizePrimary(activeRoute) == targetRoute) {
      onActiveDestinationTap?.call();
      return;
    }
    Navigator.of(context).pushReplacementNamed(targetRoute);
  }

  List<_PrimaryDestination> get _resolvedDestinations => [
        for (final destination in _primaryDestinations)
          destination.route == AppRoutes.workspace
              ? _PrimaryDestination(
                  route: destination.route,
                  label: destination.label,
                  icon: workspaceIcon ?? destination.icon,
                  selectedIcon: workspaceSelectedIcon ??
                      workspaceIcon ??
                      destination.selectedIcon,
                )
              : destination,
      ];
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
    route: AppRoutes.flow,
    label: 'Flow',
    icon: Icons.auto_awesome_motion_outlined,
    selectedIcon: Icons.auto_awesome_motion,
  ),
  _PrimaryDestination(
    route: AppRoutes.insights,
    label: 'Insights',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
  ),
  _PrimaryDestination(
    route: AppRoutes.boardConfiguration,
    label: 'Configuration',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
  ),
];
