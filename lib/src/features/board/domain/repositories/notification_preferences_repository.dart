import '../models/notification_preferences.dart';

abstract class NotificationPreferencesRepository {
  Future<NotificationPreferences> load();
  Future<NotificationPreferences> save(NotificationPreferences preferences);
}
