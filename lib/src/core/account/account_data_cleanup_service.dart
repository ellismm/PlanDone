import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../features/auth/domain/models/auth_failure.dart';

abstract class AccountDeletionPreflightService {
  Future<void> requireRecentAuthentication();
}

class NoopAccountDeletionPreflightService
    implements AccountDeletionPreflightService {
  const NoopAccountDeletionPreflightService();

  @override
  Future<void> requireRecentAuthentication() async {}
}

class FirebaseAccountDeletionPreflightService
    implements AccountDeletionPreflightService {
  FirebaseAccountDeletionPreflightService({
    required FirebaseAuth firebaseAuth,
    DateTime Function()? now,
  })  : _firebaseAuth = firebaseAuth,
        _now = now ?? DateTime.now;

  static const maximumAuthenticationAge = Duration(minutes: 2);

  final FirebaseAuth _firebaseAuth;
  final DateTime Function() _now;

  @override
  Future<void> requireRecentAuthentication() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AuthFailure(
        code: AuthFailureCode.requiresRecentLogin,
        message: 'Sign in again before deleting your account.',
      );
    }

    try {
      final tokenResult = await user.getIdTokenResult();
      if (!AccountDeletionRecencyPolicy.isRecent(
        authTime: tokenResult.authTime,
        now: _now(),
        maximumAge: maximumAuthenticationAge,
      )) {
        throw const AuthFailure(
          code: AuthFailureCode.requiresRecentLogin,
          message:
              'For security, sign out and sign in again before deleting your account.',
        );
      }
    } on AuthFailure {
      rethrow;
    } catch (_) {
      throw const AuthFailure(
        code: AuthFailureCode.unavailable,
        message:
            'PlanDone could not verify your recent sign-in. Check connectivity and try again.',
      );
    }
  }
}

class AccountDeletionRecencyPolicy {
  const AccountDeletionRecencyPolicy._();

  static bool isRecent({
    required DateTime? authTime,
    required DateTime now,
    required Duration maximumAge,
  }) {
    if (authTime == null) return false;
    final age = now.toUtc().difference(authTime.toUtc());
    return !age.isNegative && age <= maximumAge;
  }
}

abstract class AccountDataCleanupService {
  Future<void> deleteCloudData({required String userId});
}

class NoopAccountDataCleanupService implements AccountDataCleanupService {
  const NoopAccountDataCleanupService();

  @override
  Future<void> deleteCloudData({required String userId}) async {}
}

class FirestoreAccountDataCleanupService implements AccountDataCleanupService {
  FirestoreAccountDataCleanupService({
    required FirebaseFirestore firestore,
  }) : _firestore = firestore;

  static const _batchSize = 400;
  static const _ownedBoardSubcollections = <String>[
    'workItems',
    'columns',
    '_appliedOps',
  ];

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _boards =>
      _firestore.collection('boards');

  @override
  Future<void> deleteCloudData({required String userId}) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) {
      throw ArgumentError.value(userId, 'userId', 'Must not be empty.');
    }

    // Discover memberships before deleting anything. The collection-group
    // query makes account deletion complete even after a reinstall, when the
    // local board catalog may no longer contain shared boards.
    final membershipSnapshot = await _firestore
        .collectionGroup('members')
        .where('userId', isEqualTo: normalizedUserId)
        .get();
    final ownedBoardSnapshot =
        await _boards.where('ownerId', isEqualTo: normalizedUserId).get();

    final ownedBoards = <String, DocumentReference<Map<String, dynamic>>>{
      for (final board in ownedBoardSnapshot.docs) board.id: board.reference,
    };

    final sharedMemberships = <DocumentReference<Map<String, dynamic>>>[];
    for (final membership in membershipSnapshot.docs) {
      final board = membership.reference.parent.parent;
      if (board == null || ownedBoards.containsKey(board.id)) continue;
      sharedMemberships.add(membership.reference);
    }

    // Leaving shared boards first prevents the account from retaining access
    // while its owned content is being removed. Shared board content belongs
    // to that board and is intentionally retained for its remaining members.
    await _deleteReferences(sharedMemberships);

    for (final board in ownedBoards.values) {
      await _deleteOwnedBoard(
        board: board,
        ownerId: normalizedUserId,
      );
    }

    final user = _firestore.collection('users').doc(normalizedUserId);
    await _deleteCollection(user.collection('devices'));
    await user.delete();
  }

  Future<void> _deleteOwnedBoard({
    required DocumentReference<Map<String, dynamic>> board,
    required String ownerId,
  }) async {
    final members = board.collection('members');

    // Revoke collaborators before removing board content so they cannot add
    // new documents during the cleanup window.
    await _deleteCollection(members, exceptDocumentId: ownerId);

    for (final collectionName in _ownedBoardSubcollections) {
      await _deleteCollection(board.collection(collectionName));
    }

    // The final atomic batch preserves owner authorization until the board and
    // its protected owner membership disappear together.
    final batch = _firestore.batch();
    batch.delete(members.doc(ownerId));
    batch.delete(board);
    await batch.commit();
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection, {
    String? exceptDocumentId,
  }) async {
    while (true) {
      final snapshot = await collection.limit(_batchSize).get();
      if (snapshot.docs.isEmpty) return;

      final references = snapshot.docs
          .where((doc) => doc.id != exceptDocumentId)
          .map((doc) => doc.reference)
          .toList(growable: false);
      if (references.isEmpty) return;

      await _deleteReferences(references);
    }
  }

  Future<void> _deleteReferences(
    List<DocumentReference<Map<String, dynamic>>> references,
  ) async {
    for (var offset = 0; offset < references.length; offset += _batchSize) {
      final nextOffset = offset + _batchSize;
      final end =
          nextOffset < references.length ? nextOffset : references.length;
      final batch = _firestore.batch();
      for (final reference in references.sublist(offset, end)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
  }
}
