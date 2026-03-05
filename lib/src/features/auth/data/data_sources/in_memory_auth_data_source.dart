import 'dart:async';

import '../../domain/models/auth_user.dart';
import 'auth_data_source.dart';

class InMemoryAuthDataSource implements AuthDataSource {
  InMemoryAuthDataSource({AuthSession? initialSession})
      : _session = initialSession {
    _controller = StreamController<AuthSession?>.broadcast();
  }

  AuthSession? _session;
  late final StreamController<AuthSession?> _controller;

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
    final session = AuthSession(
      user: AuthUser(
        uid: _uidFromEmail(email),
        email: email,
        displayName: email.split('@').first,
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
  }) {
    return signInWithEmailPassword(email: email, password: password);
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    final session = const AuthSession(
      user: AuthUser(
        uid: 'google-user',
        email: 'google-user@plandone.local',
        displayName: 'Google User',
      ),
    );
    _session = session;
    _notifyListeners();
    return session;
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
