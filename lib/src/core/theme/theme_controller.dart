import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/board/presentation/board_controller.dart';
import 'plan_done_theme.dart';
import 'theme_settings_repository.dart';

final themeSettingsRepositoryProvider = Provider<ThemeSettingsRepository>((ref) {
  const useDrift = bool.fromEnvironment('USE_DRIFT_LOCAL_STORE', defaultValue: false);
  if (useDrift) {
    return DriftThemeSettingsRepository(ref.watch(boardDatabaseProvider));
  }
  return InMemoryThemeSettingsRepository();
});

final themeControllerProvider = AsyncNotifierProvider<ThemeController, PlanDoneThemeKey>(
  ThemeController.new,
);

class ThemeController extends AsyncNotifier<PlanDoneThemeKey> {
  late final ThemeSettingsRepository _repository;

  @override
  Future<PlanDoneThemeKey> build() async {
    _repository = ref.watch(themeSettingsRepositoryProvider);
    return _repository.loadSelectedTheme();
  }

  Future<void> setTheme(PlanDoneThemeKey key) async {
    state = AsyncData(key);
    await _repository.saveSelectedTheme(key);
  }
}
