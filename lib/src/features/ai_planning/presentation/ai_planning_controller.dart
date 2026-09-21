import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/runtime/runtime_flags.dart';
import '../../board/presentation/board_controller.dart';
import '../application/ai_planning_commit_service.dart';
import '../data/firebase_ai_planning_provider.dart';
import '../domain/ai_planning_provider.dart';

final aiPlanningProviderProvider = Provider<AiPlanningProvider>((ref) {
  if (!useFirebaseAi) {
    return const UnavailableAiPlanningProvider();
  }
  return FirebaseAiPlanningProvider(
    modelName: firebaseAiModel,
    fallbackModelName: firebaseAiFallbackModel,
  );
});

final aiPlanningCommitServiceProvider = Provider<AiPlanningCommitService>(
  (ref) => AiPlanningCommitService(
    repository: ref.watch(boardRepositoryProvider),
  ),
);
