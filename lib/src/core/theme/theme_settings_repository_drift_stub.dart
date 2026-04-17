import 'plan_done_theme.dart';
import 'theme_settings_repository.dart';

class DriftThemeSettingsRepository implements ThemeSettingsRepository {
  final InMemoryThemeSettingsRepository _delegate =
      InMemoryThemeSettingsRepository();

  DriftThemeSettingsRepository(Object database);

  @override
  Future<PlanDoneThemeKey> loadSelectedTheme() {
    return _delegate.loadSelectedTheme();
  }

  @override
  Future<void> saveSelectedTheme(PlanDoneThemeKey key) {
    return _delegate.saveSelectedTheme(key);
  }
}
