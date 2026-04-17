import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/core/help/app_help.dart';
import 'package:plandone/src/core/help/app_help_controller.dart';

void main() {
  test('in-memory help preferences persist per user', () async {
    final userOneRepo =
        InMemoryAppHelpPreferencesRepository(userId: 'help-user-1');
    final userTwoRepo =
        InMemoryAppHelpPreferencesRepository(userId: 'help-user-2');

    await userOneRepo.save(
      const AppHelpPreferences(
        showFloatingHelpButton: true,
        completedTours: {AppHelpTourId.flow},
      ),
    );

    expect(
      await userOneRepo.load(),
      const AppHelpPreferences(
        showFloatingHelpButton: true,
        completedTours: {AppHelpTourId.flow},
      ),
    );
    expect(
      await userTwoRepo.load(),
      const AppHelpPreferences(),
    );
  });
}
