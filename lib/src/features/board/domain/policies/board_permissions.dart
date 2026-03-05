import '../models/board_member.dart';
import '../models/board_snapshot.dart';

enum BoardCapability {
  read,
  modifyItems,
  manageBoard,
  manageMembers,
  configureValidation,
  joinInvite,
}

class BoardPermissionProfile {
  const BoardPermissionProfile({
    required this.member,
    required this.capabilities,
  });

  final BoardMember? member;
  final Set<BoardCapability> capabilities;

  bool has(BoardCapability capability) => capabilities.contains(capability);
}

class BoardPermissions {
  static const int pendingInviteEpochMillis = 0;

  static BoardMember? memberForUser(BoardSnapshot snapshot, String userId) {
    return snapshot.members
        .where((member) => member.userId == userId)
        .cast<BoardMember?>()
        .firstWhere(
          (_) => true,
          orElse: () => null,
        );
  }

  static bool isInvitePending(BoardMember? member) {
    if (member == null) return false;
    return member.joinedAt.millisecondsSinceEpoch <= pendingInviteEpochMillis;
  }

  static bool canRead(BoardMember? member) => member != null;

  static bool canModifyItems(BoardMember? member) {
    if (member == null || isInvitePending(member)) return false;
    return member.role == BoardRole.member ||
        member.role == BoardRole.admin ||
        member.role == BoardRole.owner;
  }

  static bool canManageBoard(BoardMember? member) {
    if (member == null || isInvitePending(member)) return false;
    return member.role == BoardRole.admin || member.role == BoardRole.owner;
  }

  static bool canManageMembers(BoardMember? member) => canManageBoard(member);

  static bool canConfigureValidation(BoardMember? member) =>
      canManageBoard(member);

  static bool canJoinInvite({
    required BoardMember? member,
    required String userId,
  }) {
    if (member == null) return false;
    return member.userId == userId && isInvitePending(member);
  }

  static BoardPermissionProfile profileFor({
    required BoardSnapshot snapshot,
    required String userId,
  }) {
    final member = memberForUser(snapshot, userId);
    final capabilities = <BoardCapability>{};
    if (canRead(member)) capabilities.add(BoardCapability.read);
    if (canModifyItems(member)) capabilities.add(BoardCapability.modifyItems);
    if (canManageBoard(member)) capabilities.add(BoardCapability.manageBoard);
    if (canManageMembers(member)) {
      capabilities.add(BoardCapability.manageMembers);
    }
    if (canConfigureValidation(member)) {
      capabilities.add(BoardCapability.configureValidation);
    }
    if (canJoinInvite(member: member, userId: userId)) {
      capabilities.add(BoardCapability.joinInvite);
    }

    return BoardPermissionProfile(member: member, capabilities: capabilities);
  }
}
