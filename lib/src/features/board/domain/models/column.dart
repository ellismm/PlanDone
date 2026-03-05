enum BoardColumnKind {
  planning,
  backlog,
  ready,
  inProgress,
  blocked,
  urgent,
  review,
  done,
  cancelled,
  custom,
}

BoardColumnKind boardColumnKindFromName(String? raw) {
  if (raw == null || raw.isEmpty) return BoardColumnKind.custom;
  return BoardColumnKind.values.firstWhere(
    (kind) => kind.name == raw,
    orElse: () => BoardColumnKind.custom,
  );
}

class BoardColumn {
  const BoardColumn({
    required this.columnId,
    required this.boardId,
    required this.name,
    required this.orderIndex,
    this.kind = BoardColumnKind.custom,
    this.isDoneState = false,
    this.isBlockedState = false,
    this.isCancelledState = false,
    this.isDesignated = false,
    this.isEnabled = true,
  });

  final String columnId;
  final String boardId;
  final String name;
  final int orderIndex;
  final BoardColumnKind kind;
  final bool isDoneState;
  final bool isBlockedState;
  final bool isCancelledState;
  final bool isDesignated;
  final bool isEnabled;

  BoardColumn copyWith({
    String? name,
    int? orderIndex,
    BoardColumnKind? kind,
    bool? isDoneState,
    bool? isBlockedState,
    bool? isCancelledState,
    bool? isDesignated,
    bool? isEnabled,
  }) {
    return BoardColumn(
      columnId: columnId,
      boardId: boardId,
      name: name ?? this.name,
      orderIndex: orderIndex ?? this.orderIndex,
      kind: kind ?? this.kind,
      isDoneState: isDoneState ?? this.isDoneState,
      isBlockedState: isBlockedState ?? this.isBlockedState,
      isCancelledState: isCancelledState ?? this.isCancelledState,
      isDesignated: isDesignated ?? this.isDesignated,
      isEnabled: isEnabled ?? this.isEnabled,
    );
  }
}
