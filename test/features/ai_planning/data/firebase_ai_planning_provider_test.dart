import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/ai_planning/data/firebase_ai_planning_provider.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_draft.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  test('uses JSON mode without the rejected response schema parameter', () {
    final config = FirebaseAiPlanningProvider.generationConfig().toJson();

    expect(config['responseMimeType'], 'application/json');
    expect(config, isNot(contains('responseSchema')));
    expect(config, isNot(contains('responseJsonSchema')));
  });

  test('requests complete hierarchy decomposition by default', () {
    const request = AiPlanningRequest(
      prompt: 'Create a complete plan for refinishing a garage floor.',
      boardName: 'Home',
    );

    final payload = FirebaseAiPlanningProvider.requestPayloadFor(request);

    expect(payload['hierarchyPreference'], 'complete');
    expect(payload['maximumItems'], 32);
  });

  test('sends existing ancestry and exact requested-parent context', () {
    const request = AiPlanningRequest(
      prompt: 'Plan the garage floor under home maintenance.',
      boardName: 'Home',
      placementMode: AiPlanningPlacementMode.existingParent,
      requestedParentItemId: 'goal-home',
      existingItems: [
        AiPlanningExistingItem(
          itemId: 'goal-home',
          title: 'Home Maintenance',
          type: WorkItemType.goal,
        ),
        AiPlanningExistingItem(
          itemId: 'project-garage',
          title: 'Garage Improvements',
          type: WorkItemType.project,
          parentItemId: 'goal-home',
        ),
      ],
    );

    final payload = FirebaseAiPlanningProvider.requestPayloadFor(request);
    final existingItems = payload['existingItems']! as List<Object?>;
    final garage = existingItems[1]! as Map<String, Object?>;
    final placement = payload['placement']! as Map<String, Object?>;

    expect(garage['parentId'], 'goal-home');
    expect(
      placement['requestedParent'],
      {
        'id': 'goal-home',
        'title': 'Home Maintenance',
        'type': 'goal',
      },
    );
  });

  test('retries once with the free fallback only after a quota error',
      () async {
    final calls = <String>[];
    final provider = FirebaseAiPlanningProvider(
      modelName: 'gemini-3.7-flash',
      fallbackModelName: 'gemini-3.5-flash-lite',
      modelRunner: (modelName, request, isFallback) async {
        calls.add(modelName);
        if (!isFallback) {
          throw QuotaExceeded('429 RESOURCE_EXHAUSTED');
        }
        return _draftFrom(modelName, isFallback: isFallback);
      },
    );

    final draft = await provider.generate(_request);

    expect(calls, ['gemini-3.7-flash', 'gemini-3.5-flash-lite']);
    expect(draft.providerName, contains('free fallback'));
  });

  test('does not use the fallback for a non-quota error', () async {
    final calls = <String>[];
    final provider = FirebaseAiPlanningProvider(
      modelName: 'gemini-3.7-flash',
      fallbackModelName: 'gemini-3.5-flash-lite',
      modelRunner: (modelName, request, isFallback) async {
        calls.add(modelName);
        throw ServerException('500 INTERNAL: unavailable');
      },
    );

    await expectLater(
      provider.generate(_request),
      throwsA(isA<AiPlanningException>()),
    );
    expect(calls, ['gemini-3.7-flash']);
  });

  test('uses the free fallback when the primary model reports high demand',
      () async {
    final calls = <String>[];
    final provider = FirebaseAiPlanningProvider(
      modelName: 'gemini-3.7-flash',
      fallbackModelName: 'gemini-3.5-flash-lite',
      modelRunner: (modelName, request, isFallback) async {
        calls.add(modelName);
        if (!isFallback) {
          throw ServerException(
            '500: This model is currently experiencing high demand.',
          );
        }
        return _draftFrom(modelName, isFallback: isFallback);
      },
    );

    final draft = await provider.generate(_request);

    expect(calls, ['gemini-3.7-flash', 'gemini-3.5-flash-lite']);
    expect(draft.providerName, contains('free fallback'));
  });

  test('uses the free fallback when the SDK cannot decode the primary response',
      () async {
    final calls = <String>[];
    final provider = FirebaseAiPlanningProvider(
      modelName: 'gemini-3.5-flash',
      fallbackModelName: 'gemini-3.5-flash-lite',
      modelRunner: (modelName, request, isFallback) async {
        calls.add(modelName);
        if (!isFallback) {
          throw const FormatException('Unexpected character in response');
        }
        return _draftFrom(modelName, isFallback: isFallback);
      },
    );

    final draft = await provider.generate(_request);

    expect(calls, ['gemini-3.5-flash', 'gemini-3.5-flash-lite']);
    expect(draft.providerName, contains('free fallback'));
  });

  test('stops waiting after the configured request timeout', () async {
    final provider = FirebaseAiPlanningProvider(
      modelName: 'gemini-3.7-flash',
      fallbackModelName: 'gemini-3.5-flash-lite',
      requestTimeout: const Duration(milliseconds: 10),
      modelRunner: (modelName, request, isFallback) async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return _draftFrom(modelName, isFallback: isFallback);
      },
    );

    await expectLater(
      provider.generate(_request),
      throwsA(
        isA<AiPlanningException>().having(
          (error) => error.message,
          'message',
          contains('within one minute'),
        ),
      ),
    );
  });

  group('FirebaseAiPlanningProvider.userMessageFor', () {
    test('identifies free-tier quota exhaustion', () {
      expect(
        FirebaseAiPlanningProvider.userMessageFor(
          QuotaExceeded('RESOURCE_EXHAUSTED: quota exceeded'),
        ),
        contains('free-tier quota'),
      );
    });

    test('identifies App Check authorization failures', () {
      expect(
        FirebaseAiPlanningProvider.userMessageFor(
          ServerException('403 PERMISSION_DENIED: App Check token rejected'),
        ),
        contains('Firebase App Check'),
      );
    });

    test('surfaces a concise invalid request reason', () {
      expect(
        FirebaseAiPlanningProvider.userMessageFor(
          ServerException(
            '400 INVALID_ARGUMENT: response schema is not supported by model',
          ),
        ),
        contains('response schema is not supported by model'),
      );
    });

    test('identifies temporary model capacity failures', () {
      expect(
        FirebaseAiPlanningProvider.userMessageFor(
          ServerException(
            '500: This model is currently experiencing high demand.',
          ),
        ),
        contains('temporarily busy'),
      );
    });

    test('limits unexpected server details to a readable length', () {
      final message = FirebaseAiPlanningProvider.userMessageFor(
        ServerException('server detail ${'x' * 300}'),
      );

      expect(message, contains('Firebase AI returned an error'));
      expect(message.length, lessThan(240));
    });
  });

  group('FirebaseAiPlanningProvider.planningExceptionFor', () {
    test('identifies App Check token failures outside the AI SDK', () {
      final mapped = FirebaseAiPlanningProvider.planningExceptionFor(
        FirebaseException(
          plugin: 'firebase_app_check',
          code: 'unknown',
          message: 'Play Integrity attestation failed',
        ),
      );

      expect(mapped.message, contains('App Tester installation'));
    });

    test('surfaces an unexpected error detail instead of a catch-all', () {
      final mapped = FirebaseAiPlanningProvider.planningExceptionFor(
        StateError('response channel closed'),
      );

      expect(mapped.message, contains('response channel closed'));
      expect(mapped.message, isNot(contains('failed safely')));
    });
  });
}

const _request = AiPlanningRequest(
  prompt: 'Create a complete plan for refinishing a garage floor.',
  boardName: 'Home',
);

AiPlanningDraft _draftFrom(String modelName, {required bool isFallback}) {
  return AiPlanningDraft(
    prompt: _request.prompt,
    summary: 'A safe draft.',
    items: const [
      AiPlanningDraftItem(
        draftId: 'goal',
        title: 'Refinish the garage floor',
        type: WorkItemType.goal,
      ),
    ],
    providerName: FirebaseAiPlanningProvider.providerNameFor(
      modelName,
      isFallback: isFallback,
    ),
    createdAt: DateTime(2026, 8, 27),
  );
}
