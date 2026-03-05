import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../runtime/runtime_flags.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!useFirebasePush) return;
  await Firebase.initializeApp();
}

final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(
    messaging: FirebaseMessaging.instance,
    firestore: FirebaseFirestore.instance,
  );
  ref.onDispose(service.dispose);
  return service;
});

class PushNotificationService {
  PushNotificationService({
    required FirebaseMessaging messaging,
    required FirebaseFirestore firestore,
  })  : _messaging = messaging,
        _firestore = firestore {
    _tokenRefreshSub = _messaging.onTokenRefresh.listen((token) {
      final uid = _activeUserId;
      if (uid == null || !useFirebasePush) return;
      unawaited(_upsertDeviceToken(uid: uid, token: token));
    });
  }

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _firestore;

  String? _activeUserId;
  bool _permissionRequested = false;
  StreamSubscription<String>? _tokenRefreshSub;

  Future<void> syncForUser(String? uid) async {
    if (!useFirebasePush || uid == null || uid.trim().isEmpty) {
      _activeUserId = null;
      return;
    }
    _activeUserId = uid;

    await _ensurePermissionRequested();
    final token = await _messaging.getToken();
    if (token == null || token.trim().isEmpty) return;
    await _upsertDeviceToken(uid: uid, token: token);
  }

  Future<void> _ensurePermissionRequested() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  Future<void> _upsertDeviceToken({
    required String uid,
    required String token,
  }) async {
    final deviceId = _deviceIdFromToken(token);
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(deviceId)
        .set({
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
      'tokenPreview': token.length <= 10 ? token : token.substring(0, 10),
    }, SetOptions(merge: true));
  }

  static String _deviceIdFromToken(String token) {
    return base64Url.encode(utf8.encode(token));
  }

  Future<void> dispose() async {
    await _tokenRefreshSub?.cancel();
    _tokenRefreshSub = null;
  }
}
