String boardDatabaseNameForUser(String userId) {
  final safeUserId = userId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  return 'plandone_$safeUserId.sqlite';
}
