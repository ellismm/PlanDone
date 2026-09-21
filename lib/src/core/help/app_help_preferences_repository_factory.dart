import '../../features/board/data/platform/storage_platform_interface.dart';
import 'app_help_preferences_repository.dart';
import 'app_help_preferences_repository_factory_native.dart'
    if (dart.library.js_interop) 'app_help_preferences_repository_factory_web.dart'
    as impl;

AppHelpPreferencesRepository createAppHelpPreferencesRepository({
  required PlatformBoardDatabase database,
  required String userId,
  required bool useInMemoryLocalStore,
}) {
  return impl.createAppHelpPreferencesRepository(
    database: database,
    userId: userId,
    useInMemoryLocalStore: useInMemoryLocalStore,
  );
}
