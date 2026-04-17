import '../models/board_flow.dart';

abstract class BoardFlowPreferencesRepository {
  Future<BoardFlowPreferences> load();
  Future<BoardFlowPreferences> save(BoardFlowPreferences preferences);
}
