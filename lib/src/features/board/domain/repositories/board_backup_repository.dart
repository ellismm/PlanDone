import '../models/board.dart';
import '../models/board_backup_document.dart';

abstract class BoardBackupRepository {
  Future<BoardBackupFile> exportBoard({
    required String boardId,
  });

  Future<List<BoardBackupFile>> listBackups();

  Future<Board> importBackup({
    required String backupPath,
  });

  Future<void> deleteBackup({
    required String backupPath,
  });
}
