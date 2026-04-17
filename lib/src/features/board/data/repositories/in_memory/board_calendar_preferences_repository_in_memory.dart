import '../../../domain/models/board_calendar_preferences.dart';
import '../../../domain/repositories/board_calendar_preferences_repository.dart';

class InMemoryBoardCalendarPreferencesRepository
    implements BoardCalendarPreferencesRepository {
  InMemoryBoardCalendarPreferencesRepository({required String userId})
      : _userId = userId;

  final String _userId;

  static final Map<String, BoardCalendarPreferences> _byUser =
      <String, BoardCalendarPreferences>{};

  @override
  Future<BoardCalendarPreferences> load() async {
    return _byUser[_userId] ?? const BoardCalendarPreferences();
  }

  @override
  Future<BoardCalendarPreferences> save(
    BoardCalendarPreferences preferences,
  ) async {
    _byUser[_userId] = preferences;
    return preferences;
  }
}
