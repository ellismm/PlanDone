class AppRoutes {
  static const workspace = '/workspace';
  static const flow = '/flow';
  static const insights = '/insights';
  static const boardConfiguration = '/board-configuration';
  static const planning = '/planning';
  static const aiPlanning = '/ai-planning';

  static const primary = [
    workspace,
    flow,
    insights,
    boardConfiguration,
  ];

  static String normalizePrimary(String? routeName) {
    if (primary.contains(routeName)) {
      return routeName!;
    }
    return workspace;
  }
}
