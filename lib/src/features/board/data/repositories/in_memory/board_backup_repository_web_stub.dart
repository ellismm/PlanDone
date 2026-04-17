import '../../../domain/models/board.dart';
import '../../../domain/models/board_backup_document.dart';
import '../../../domain/repositories/board_backup_repository.dart';

class WebBoardBackupRepository implements BoardBackupRepository {
  const WebBoardBackupRepository();

  Never _unsupported() {
    throw UnsupportedError(
      'Board backup import/export is not available in web preview yet.',
    );
  }

  @override
  Future<void> deleteBackup({required String backupPath}) async {}

  @override
  Future<BoardBackupFile> exportBoard({required String boardId}) async {
    _unsupported();
  }

  @override
  Future<Board> importBackup({required String backupPath}) async {
    _unsupported();
  }

  @override
  Future<List<BoardBackupFile>> listBackups() async {
    return const <BoardBackupFile>[];
  }
}
