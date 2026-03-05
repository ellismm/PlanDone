import '../models/column.dart';

class WorkflowTemplateColumnSpec {
  const WorkflowTemplateColumnSpec({
    required this.idSuffix,
    required this.name,
    required this.kind,
    this.isDoneState = false,
    this.isBlockedState = false,
    this.isCancelledState = false,
    this.isEnabledByDefault = true,
  });

  final String idSuffix;
  final String name;
  final BoardColumnKind kind;
  final bool isDoneState;
  final bool isBlockedState;
  final bool isCancelledState;
  final bool isEnabledByDefault;
}

class WorkflowSemanticsPolicy {
  static const List<WorkflowTemplateColumnSpec> designatedStarterTemplate = [
    WorkflowTemplateColumnSpec(
      idSuffix: 'planning',
      name: 'Planning',
      kind: BoardColumnKind.planning,
    ),
    WorkflowTemplateColumnSpec(
      idSuffix: 'backlog',
      name: 'Backlog',
      kind: BoardColumnKind.backlog,
    ),
    WorkflowTemplateColumnSpec(
      idSuffix: 'ready',
      name: 'Ready',
      kind: BoardColumnKind.ready,
    ),
    WorkflowTemplateColumnSpec(
      idSuffix: 'in-progress',
      name: 'In Progress',
      kind: BoardColumnKind.inProgress,
    ),
    WorkflowTemplateColumnSpec(
      idSuffix: 'blocked',
      name: 'Blocked',
      kind: BoardColumnKind.blocked,
      isBlockedState: true,
      isEnabledByDefault: false,
    ),
    WorkflowTemplateColumnSpec(
      idSuffix: 'urgent',
      name: 'Urgent',
      kind: BoardColumnKind.urgent,
      isEnabledByDefault: false,
    ),
    WorkflowTemplateColumnSpec(
      idSuffix: 'review',
      name: 'Review',
      kind: BoardColumnKind.review,
    ),
    WorkflowTemplateColumnSpec(
      idSuffix: 'done',
      name: 'Done',
      kind: BoardColumnKind.done,
      isDoneState: true,
    ),
    WorkflowTemplateColumnSpec(
      idSuffix: 'cancelled',
      name: 'Cancelled',
      kind: BoardColumnKind.cancelled,
      isCancelledState: true,
      isDoneState: true,
      isEnabledByDefault: false,
    ),
  ];

  static List<BoardColumn> legacyDefaultColumns(String boardId) {
    final usesGlobalIds = boardId == 'board-1';
    String scoped(String suffix) {
      return usesGlobalIds ? 'c-$suffix' : '$boardId-c-$suffix';
    }

    return [
      BoardColumn(
        columnId: scoped('todo'),
        boardId: boardId,
        name: 'To Do',
        orderIndex: 0,
        kind: BoardColumnKind.backlog,
      ),
      BoardColumn(
        columnId: scoped('doing'),
        boardId: boardId,
        name: 'Doing',
        orderIndex: 1,
        kind: BoardColumnKind.inProgress,
      ),
      BoardColumn(
        columnId: scoped('done'),
        boardId: boardId,
        name: 'Done',
        orderIndex: 2,
        kind: BoardColumnKind.done,
        isDoneState: true,
      ),
    ];
  }

  static String _normalize(String raw) {
    return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static BoardColumnKind _inferKind(BoardColumn column) {
    final token = _normalize('${column.columnId} ${column.name}');

    if (token.contains('cancel')) return BoardColumnKind.cancelled;
    if (token.contains('done') ||
        token.contains('complete') ||
        token.contains('closed')) {
      return BoardColumnKind.done;
    }
    if (token.contains('block') || token.contains('hold')) {
      return BoardColumnKind.blocked;
    }
    if (token.contains('review') || token.contains('qa')) {
      return BoardColumnKind.review;
    }
    if (token.contains('urgent')) return BoardColumnKind.urgent;
    if (token.contains('progress') ||
        token.contains('doing') ||
        token.contains('active')) {
      return BoardColumnKind.inProgress;
    }
    if (token.contains('ready') || token.contains('next')) {
      return BoardColumnKind.ready;
    }
    if (token.contains('plan')) return BoardColumnKind.planning;
    if (token.contains('backlog') ||
        token.contains('todo') ||
        token.contains('queue')) {
      return BoardColumnKind.backlog;
    }

    return BoardColumnKind.custom;
  }

  static BoardColumn withLegacyInference(BoardColumn column) {
    final hasExplicitSemantics = column.kind != BoardColumnKind.custom ||
        column.isDoneState ||
        column.isBlockedState ||
        column.isCancelledState ||
        column.isDesignated;
    if (hasExplicitSemantics) return column;

    final inferredKind = _inferKind(column);
    return column.copyWith(
      kind: inferredKind,
      isDoneState: inferredKind == BoardColumnKind.done ||
          inferredKind == BoardColumnKind.cancelled,
      isBlockedState: inferredKind == BoardColumnKind.blocked,
      isCancelledState: inferredKind == BoardColumnKind.cancelled,
    );
  }

  static List<BoardColumn> normalizeColumns(Iterable<BoardColumn> columns) {
    return columns.map(withLegacyInference).toList();
  }

  static BoardColumn? doneColumn(Iterable<BoardColumn> columns) {
    final normalized = normalizeColumns(columns)
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return normalized
        .where((column) => column.isEnabled && column.isDoneState)
        .cast<BoardColumn?>()
        .firstWhere((_) => true, orElse: () => null);
  }

  static List<BoardColumn> designatedTemplateColumns(String boardId) {
    return [
      for (var i = 0; i < designatedStarterTemplate.length; i++)
        BoardColumn(
          columnId: '$boardId-c-${designatedStarterTemplate[i].idSuffix}',
          boardId: boardId,
          name: designatedStarterTemplate[i].name,
          orderIndex: i,
          kind: designatedStarterTemplate[i].kind,
          isDoneState: designatedStarterTemplate[i].isDoneState,
          isBlockedState: designatedStarterTemplate[i].isBlockedState,
          isCancelledState: designatedStarterTemplate[i].isCancelledState,
          isDesignated: true,
          isEnabled: designatedStarterTemplate[i].isEnabledByDefault,
        ),
    ];
  }
}
