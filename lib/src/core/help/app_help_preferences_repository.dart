import 'app_help.dart';

abstract class AppHelpPreferencesRepository {
  Future<AppHelpPreferences> load();

  Future<AppHelpPreferences> save(AppHelpPreferences preferences);
}

class InMemoryAppHelpPreferencesRepository
    implements AppHelpPreferencesRepository {
  InMemoryAppHelpPreferencesRepository({required String userId})
      : _userId = userId;

  final String _userId;

  static final Map<String, AppHelpPreferences> _byUser =
      <String, AppHelpPreferences>{};

  @override
  Future<AppHelpPreferences> load() async {
    return _byUser[_userId] ?? const AppHelpPreferences();
  }

  @override
  Future<AppHelpPreferences> save(AppHelpPreferences preferences) async {
    _byUser[_userId] = preferences;
    return preferences;
  }
}
