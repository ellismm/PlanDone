enum BoardRole {
  viewer,
  member,
  admin,
  owner,
}

class BoardMember {
  const BoardMember({
    required this.boardId,
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  final String boardId;
  final String userId;
  final BoardRole role;
  final DateTime joinedAt;
}
