import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'src/core/notifications/push_notification_service.dart';
import 'src/core/runtime/app_bootstrap_state.dart';
import 'src/core/runtime/runtime_flags.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var bootstrapState = const AppBootstrapState.ready();
  final runtimeConfigurationError = validateRuntimeConfiguration();
  if (runtimeConfigurationError != null) {
    bootstrapState = AppBootstrapState.firebaseUnavailable(
      'Invalid PlanDone runtime profile: $runtimeConfigurationError',
    );
  } else if (useFirebaseAuth || useFirebaseSync || useFirebasePush) {
    try {
      await Firebase.initializeApp();
    } catch (error) {
      bootstrapState = AppBootstrapState.firebaseUnavailable(
        'Firebase is not configured for this Android build yet. Add google-services.json and enable the Firebase providers you want to use.',
      );
    }
  }
  if (useFirebaseAi && bootstrapState.firebaseReady) {
    try {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestProvider(),
      );
    } catch (_) {
      // AI requests surface App Check failures without blocking the rest of
      // the local-first application.
    }
  }
  if (useFirebasePush && bootstrapState.firebaseReady) {
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
