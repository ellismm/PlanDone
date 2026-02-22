class BoardColumn {
  const BoardColumn({
    required this.columnId,
    required this.boardId,
    required this.name,
    required this.orderIndex,
  });

  final String columnId;
  final String boardId;
  final String name;
  final int orderIndex;
}
