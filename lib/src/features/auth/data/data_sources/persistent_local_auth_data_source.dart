import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/models/auth_failure.dart';
import '../../domain/models/auth_user.dart';
import 'auth_data_source.dart';

class PersistentLocalAuthDataSource implements AuthDataSource {
  PersistentLocalAuthDataSource({
    LocalAuthKeyValueStore? store,
  }) : _store = store ?? SecureStorageLocalAuthKeyValueStore();

  static const _usersKey = 'auth.local.users';
  static const _sessionKey = 'auth.local.session';

  final LocalAuthKeyValueStore _store;
  final Map<String, _StoredUser> _users = <String, _StoredUser>{};
  final StreamController<AuthSession?> _controller =
      StreamController<AuthSession?>.broadcast();

  AuthSession? _session;
  bool _loaded = false;
  Future<void>? _loadInFlight;

  @override
  Stream<AuthSession?> authStateChanges() async* {
    await _ensureLoaded();
    yield _session;
    yield* _controller.stream;
  }

  @override
  Future<AuthSession> signInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    await _ensureLoaded();
    final normalizedEmail = email.trim().toLowerCase();
    final user = _users[normalizedEmail];
    if (user == null) {
      throw const AuthFailure(
        code: AuthFailureCode.userNotFound,
        message:
            'No local account was found for that email on this device. If this was your older device-local account, use Sign up with the same email to reconnect to your local workspace.',
      );
    }
    if (user.password != password) {
      throw const AuthFailure(
        code: AuthFailureCode.wrongPassword,
        message: 'Incorrect email or password.',
      );
    }
    final session = user.toSession();
    _session = session;
    await _persistSession();
    _notifyListeners();
    return session;
  }

  @override
  Future<AuthSession> signUpWithEmailPassword({
    required String email,
    required String password,
    required String displayName,
  }) async {
    await _ensureLoaded();
    final normalizedEmail = email.trim().toLowerCase();
    if (_users.containsKey(normalizedEmail)) {
      throw const AuthFailure(
        code: AuthFailureCode.duplicateEmail,
        message: 'An account already exists for that email on this device.',
      );
    }
    final storedUser = _StoredUser(
      uid: _uidFromEmail(normalizedEmail),
      email: normalizedEmail,
      displayName: displayName.trim(),
      password: password,
    );
    _users[normalizedEmail] = storedUser;
    await _persistUsers();
    final session = storedUser.toSession();
    _session = session;
    await _persistSession();
    _notifyListeners();
    return session;
  }

  @override
  Future<AuthSession> signInWithGoogle() async {
    await _ensureLoaded();
    const email = 'google-user@plandone.local';
    final storedUser = _users.putIfAbsent(
      email,
      () => const _StoredUser(
        uid: 'google-user',
        email: email,
        displayName: 'Google User',
        password: '',
      ),
    );
    await _persistUsers();
    final session = storedUser.toSession();
    _session = session;
    await _persistSession();
    _notifyListeners();
    return session;
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
  }) async {}

  @override
  Future<void> deleteAccount() async {
    await _ensureLoaded();
    final session = _session;
    if (session == null) return;
    final normalizedEmail = session.user.email?.trim().toLowerCase();
    if (normalizedEmail != null) {
      _users.remove(normalizedEmail);
      await _persistUsers();
    }
    _session = null;
    await _store.delete(_sessionKey);
    _notifyListeners();
  }

  @override
  Future<void> signOut() async {
    await _ensureLoaded();
    _session = null;
    await _store.delete(_sessionKey);
    _notifyListeners();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final inFlight = _loadInFlight;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final loadFuture = _loadState();
    _loadInFlight = loadFuture;
    try {
      await loadFuture;
    } finally {
      _loadInFlight = null;
    }
  }

  Future<void> _loadState() async {
    final usersJson = await _store.read(_usersKey);
    if (usersJson != null && usersJson.isNotEmpty) {
      final decoded = jsonDecode(usersJson) as List<dynamic>;
      _users
        ..clear()
        ..addEntries(
          decoded
              .cast<Map<String, dynamic>>()
              .map(_StoredUser.fromMap)
              .map((user) => MapEntry(user.email, user)),
        );
    }

    final sessionJson = await _store.read(_sessionKey);
    if (sessionJson != null && sessionJson.isNotEmpty) {
      final decoded = jsonDecode(sessionJson) as Map<String, dynamic>;
      _session = AuthSession(
        user: AuthUser(
          uid: decoded['uid'] as String,
          email: decoded['email'] as String?,
          displayName: decoded['displayName'] as String?,
          photoUrl: decoded['photoUrl'] as String?,
        ),
      );
    }

    _loaded = true;
  }

  Future<void> _persistUsers() {
    return _store.write(
      _usersKey,
      jsonEncode(_users.values.map((user) => user.toMap()).toList()),
    );
  }

  Future<void> _persistSession() async {
    final session = _session;
    if (session == null) {
      await _store.delete(_sessionKey);
      return;
    }
    await _store.write(
      _sessionKey,
      jsonEncode({
        'uid': session.user.uid,
        'email': session.user.email,
        'displayName': session.user.displayName,
        'photoUrl': session.user.photoUrl,
      }),
    );
  }

  void _notifyListeners() {
    _controller.add(_session);
  }

  String _uidFromEmail(String email) {
    return 'user-${email.trim().toLowerCase().hashCode.abs()}';
  }
}

abstract class LocalAuthKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class SecureStorageLocalAuthKeyValueStore implements LocalAuthKeyValueStore {
  SecureStorageLocalAuthKeyValueStore({
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secureStorage;

  @override
  Future<void> delete(String key) {
    return _secureStorage.delete(key: key);
  }

  @override
  Future<String?> read(String key) {
    return _secureStorage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) {
    return _secureStorage.write(key: key, value: value);
  }
}

class _StoredUser {
  const _StoredUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.password,
  });

  factory _StoredUser.fromMap(Map<String, dynamic> map) {
    return _StoredUser(
      uid: map['uid'] as String,
      email: map['email'] as String,
      displayName: map['displayName'] as String?,
      password: map['password'] as String,
    );
  }

  final String uid;
  final String email;
  final String? displayName;
  final String password;

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'password': password,
    };
  }

  AuthSession toSession() {
    return AuthSession(
      user: AuthUser(
        uid: uid,
        email: email,
        displayName: displayName,
      ),
    );
  }
}
