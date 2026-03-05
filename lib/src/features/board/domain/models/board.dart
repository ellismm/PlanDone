import 'board_validation_settings.dart';
import 'board_workflow_settings.dart';

class Board {
  const Board({
    required this.boardId,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    this.validationSettings = const BoardValidationSettings(),
    this.workflowSettings = const BoardWorkflowSettings(),
  });

  final String boardId;
  final String name;
  final String ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final BoardValidationSettings validationSettings;
  final BoardWorkflowSettings workflowSettings;

  Board copyWith({
    String? name,
    String? ownerId,
    DateTime? createdAt,
    DateTime? updatedAt,
    BoardValidationSettings? validationSettings,
    BoardWorkflowSettings? workflowSettings,
  }) {
    return Board(
      boardId: boardId,
      name: name ?? this.name,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      validationSettings: validationSettings ?? this.validationSettings,
      workflowSettings: workflowSettings ?? this.workflowSettings,
    );
  }
}
