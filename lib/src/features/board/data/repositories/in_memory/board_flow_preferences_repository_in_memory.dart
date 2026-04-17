import '../../../domain/models/board_flow.dart';
import '../../../domain/repositories/board_flow_preferences_repository.dart';

class InMemoryBoardFlowPreferencesRepository
    implements BoardFlowPreferencesRepository {
  InMemoryBoardFlowPreferencesRepository({required String userId})
      : _userId = userId;

  final String _userId;

  static final Map<String, BoardFlowPreferences> _byUser =
      <String, BoardFlowPreferences>{};

  @override
  Future<BoardFlowPreferences> load() async {
    return _byUser[_userId] ?? const BoardFlowPreferences();
  }

  @override
  Future<BoardFlowPreferences> save(BoardFlowPreferences preferences) async {
    _byUser[_userId] = preferences;
    return preferences;
  }
}
