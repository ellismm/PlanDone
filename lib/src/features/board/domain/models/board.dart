class Board {
  const Board({
    required this.boardId,
    required this.name,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String boardId;
  final String name;
  final String ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
}
