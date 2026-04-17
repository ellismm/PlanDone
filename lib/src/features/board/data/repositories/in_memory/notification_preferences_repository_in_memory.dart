import '../../../domain/models/notification_preferences.dart';
import '../../../domain/repositories/notification_preferences_repository.dart';

class InMemoryNotificationPreferencesRepository
    implements NotificationPreferencesRepository {
  InMemoryNotificationPreferencesRepository({required String userId})
      : _userId = userId;

  final String _userId;

  static final Map<String, NotificationPreferences> _byUser =
      <String, NotificationPreferences>{};

  @override
  Future<NotificationPreferences> load() async {
    return _byUser[_userId] ?? const NotificationPreferences();
  }

  @override
  Future<NotificationPreferences> save(
      NotificationPreferences preferences) async {
    _byUser[_userId] = preferences;
    return preferences;
  }
}
