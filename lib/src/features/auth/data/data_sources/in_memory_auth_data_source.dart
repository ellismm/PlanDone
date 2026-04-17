import 'dart:async';

import '../../domain/models/auth_user.dart';
import 'auth_data_source.dart';

class InMemoryAuthDataSource implements AuthDataSource {
  InMemoryAuthDataSource({AuthSession? initialSession})
      : _session = initialSession {
    _controller = StreamController<AuthSession?>.broadcast();
    if (initialSession != null) {
      final email = initialSession.user.email;
      if (email != null) {
        _users[email.trim().toLowerCase()] = _StoredUser(
          uid: initialSession.user.uid,
          email: email,
          displayName: initialSession.user.displayName,
          password: 'password-123',
        );
      }
    }
  }

  AuthSession? _session;
  late final StreamController<AuthSession?> _controller;
  final Map<String, _StoredUser> _users = <String, _StoredUser>{};

  void _notifyListeners() {
    _controller.add(_session);
  }

  @override
  Stream<AuthSession?> authStateChanges() async* {
    yield _session;
    yield* _controller.stream;
  }

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final user = _users[normalizedEmail];
    if (user == null || user.password != password) {
      throw StateError('Incorrect email or password.');
    }
    final session = AuthSession(
      user: AuthUser(
        uid: user.uid,
        email: user.email,
        displayName: user.displayName,
      ),
    );
    _session = session;
    _notifyListeners();
    return session;
  }

  @override
  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (_users.containsKey(normalizedEmail)) {
      throw StateError('An account already exists for that email.');
    }
    _users[normalizedEmail] = _StoredUser(
      uid: _uidFromEmail(normalizedEmail),
      email: normalizedEmail,
      displayName: displayName.trim(),
      password: password,
    );
    return signInWithEmailPassword(email: email, password: password);
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    const email = 'google-user@plandone.local';
    _users.putIfAbsent(
      email,
      () => _StoredUser(
        uid: 'google-user',
        email: email,
        displayName: 'Google User',
        password: '',
      ),
    );
    final session = const AuthSession(
      user: AuthUser(
        uid: 'google-user',
        email: email,
        displayName: 'Google User',
      ),
    );
    _session = session;
    _notifyListeners();
    return session;
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
  }) async {}

  @override
  Future<void> deleteAccount() async {
    final session = _session;
    if (session == null) return;
    final normalizedEmail = session.user.email?.trim().toLowerCase();
    if (normalizedEmail != null) {
      _users.remove(normalizedEmail);
    }
    _session = null;
    _notifyListeners();
  }

  @override
  Future<void> signOut() async {
    _session = null;
    _notifyListeners();
  }

  String _uidFromEmail(String email) {
    return 'user-${email.trim().toLowerCase().hashCode.abs()}';
  }
}

class _StoredUser {
  const _StoredUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.password,
  });

  final String uid;
  final String email;
  final String? displayName;
  final String password;
}
