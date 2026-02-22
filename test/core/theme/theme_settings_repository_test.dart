import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/theme/plan_done_theme.dart';
import 'package:plandone/src/core/theme/theme_settings_repository.dart';

void main() {
  test('in-memory theme repository saves and loads selected theme', () async {
    final repo = InMemoryThemeSettingsRepository();

    expect(await repo.loadSelectedTheme(), PlanDoneThemeKey.calmFocus);

    await repo.saveSelectedTheme(PlanDoneThemeKey.warmMomentum);

    expect(await repo.loadSelectedTheme(), PlanDoneThemeKey.warmMomentum);
  });
}
