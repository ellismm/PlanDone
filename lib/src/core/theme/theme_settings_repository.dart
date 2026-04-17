import 'plan_done_theme.dart';

export 'theme_settings_repository_drift.dart'
    if (dart.library.js_interop) 'theme_settings_repository_drift_stub.dart';

abstract class ThemeSettingsRepository {
  Future<PlanDoneThemeKey> loadSelectedTheme();
  Future<void> saveSelectedTheme(PlanDoneThemeKey key);
}

class InMemoryThemeSettingsRepository implements ThemeSettingsRepository {
  PlanDoneThemeKey _selected = PlanDoneThemeKey.calmFocus;

  @override
  Future<PlanDoneThemeKey> loadSelectedTheme() async => _selected;

  @override
  Future<void> saveSelectedTheme(PlanDoneThemeKey key) async {
    _selected = key;
  }
}
