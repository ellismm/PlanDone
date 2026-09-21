import 'ai_planning_draft.dart';

abstract class AiPlanningProvider {
  String get displayName;

  bool get isAvailable;

  Future<AiPlanningDraft> generate(AiPlanningRequest request);
}

class UnavailableAiPlanningProvider implements AiPlanningProvider {
  const UnavailableAiPlanningProvider({
    this.reason =
        'AI planning is not enabled for this runtime profile. Enable Firebase AI Logic and USE_FIREBASE_AI to generate a draft.',
  });

  final String reason;

  @override
  String get displayName => 'Not configured';

  @override
  bool get isAvailable => false;

  @override
  Future<AiPlanningDraft> generate(AiPlanningRequest request) {
    throw AiPlanningException(reason);
  }
}
