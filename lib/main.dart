import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'src/core/notifications/push_notification_service.dart';
import 'src/core/runtime/runtime_flags.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (useFirebaseAuth || useFirebaseSync || useFirebasePush) {
    await Firebase.initializeApp();
  }
  if (useFirebasePush) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  runApp(const ProviderScope(child: PlanDoneApp()));
}
