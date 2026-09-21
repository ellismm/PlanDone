import '../../features/board/data/platform/storage_platform_interface.dart';
import 'app_help_preferences_repository.dart';

AppHelpPreferencesRepository createAppHelpPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return InMemoryAppHelpPreferencesRepository(userId: userId);
}
