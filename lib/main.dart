import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'src/core/notifications/push_notification_service.dart';
import 'src/core/runtime/app_bootstrap_state.dart';
import 'src/core/runtime/runtime_flags.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var bootstrapState = const AppBootstrapState.ready();
  if (useFirebaseAuth || useFirebaseSync || useFirebasePush) {
    try {
      await Firebase.initializeApp();
    } catch (error) {
      bootstrapState = AppBootstrapState.firebaseUnavailable(
        'Firebase is not configured for this Android build yet. Add google-services.json and enable the Firebase providers you want to use.',
      );
    }
  }
  if (useFirebasePush) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }
  runApp(
    ProviderScope(
      overrides: [
        appBootstrapStateProvider.overrideWithValue(bootstrapState),
      ],
      child: const PlanDoneApp(),
    ),
  );
}
