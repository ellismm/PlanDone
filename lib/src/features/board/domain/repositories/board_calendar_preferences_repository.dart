import '../models/board_calendar_preferences.dart';

abstract class BoardCalendarPreferencesRepository {
  Future<BoardCalendarPreferences> load();
  Future<BoardCalendarPreferences> save(BoardCalendarPreferences preferences);
}
