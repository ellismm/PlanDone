class AppRoutes {
  static const workspace = '/workspace';
  static const boardConfiguration = '/board-configuration';
  static const planning = '/planning';

  static const primary = [
    workspace,
    boardConfiguration,
    planning,
  ];

  static String normalizePrimary(String? routeName) {
    if (primary.contains(routeName)) {
      return routeName!;
    }
    return workspace;
  }
}
