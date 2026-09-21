import 'package:flutter_test/flutter_test.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_draft.dart';
import 'package:plandone/src/features/ai_planning/domain/ai_planning_draft_parser.dart';
import 'package:plandone/src/features/board/domain/models/work_item_type.dart';

void main() {
  const parser = AiPlanningDraftParser();
  const request = AiPlanningRequest(
    prompt: 'Plan a safe product launch for a small mobile application.',
    boardName: 'Launch',
    maxItems: 12,
  );

  test('parses a strict structured hierarchy and orders parents first', () {
    final draft = parser.parse(
      '''
{
  "summary": "A reviewable launch plan.",
  "items": [
    {"id":"task-1","title":"Prepare launch checklist","type":"task","parentId":"project-1","tags":["Launch"]},
    {"id":"goal-1","title":"Ship safely","type":"goal"},
    {"id":"project-1","title":"Release the app","type":"project","parentId":"goal-1","estimatedEffortMinutes":120}
  ]
}
''',
      request: request,
      providerName: 'test provider',
      createdAt: DateTime(2026, 8, 26),
    );

    expect(draft.items, hasLength(3));
    expect(draft.items.first.tags, ['launch']);
    expect(draft.items.last.type, WorkItemType.project);
    expect(
      parser.topologicalItems(draft).map((item) => item.draftId),
      ['goal-1', 'project-1', 'task-1'],
    );
  });

  test('rejects unknown fields instead of silently accepting model drift', () {
    expect(
      () => parser.parse(
        '''
{"summary":"Unsafe","items":[{"id":"g1","title":"Goal","type":"goal","execute":"write to cloud"}]}
''',
        request: request,
        providerName: 'test provider',
      ),
      throwsA(
        isA<AiPlanningException>().having(
          (error) => error.message,
          'message',
          contains('unsupported fields'),
        ),
      ),
    );
  });

  test('rejects missing parents and invalid hierarchy direction', () {
    expect(
      () => parser.parse(
        '''
{"summary":"Missing","items":[{"id":"a1","title":"Act","type":"action","parentId":"missing"}]}
''',
        request: request,
        providerName: 'test provider',
      ),
      throwsA(
        isA<AiPlanningException>().having(
          (error) => error.message,
          'message',
          contains('missing parent'),
        ),
      ),
    );
    expect(
      () => parser.parse(
        '''
{"summary":"Wrong","items":[{"id":"a1","title":"Act","type":"action"},{"id":"g1","title":"Goal","type":"goal","parentId":"a1"}]}
''',
        request: request,
        providerName: 'test provider',
      ),
      throwsA(
        isA<AiPlanningException>().having(
          (error) => error.message,
          'message',
          contains('higher-level'),
        ),
      ),
    );
  });

  test('rejects malformed JSON and oversized output without board writes', () {
    expect(
      () => parser.parse(
        'not json',
        request: request,
        providerName: 'test provider',
      ),
      throwsA(isA<AiPlanningException>()),
    );

    const oneItemRequest = AiPlanningRequest(
      prompt: 'Create a concise plan for preparing a product release.',
      boardName: 'Launch',
      maxItems: 1,
    );
    expect(
      () => parser.parse(
        '''
{"summary":"Too many","items":[{"id":"g1","title":"One","type":"goal"},{"id":"g2","title":"Two","type":"goal"}]}
''',
        request: oneItemRequest,
        providerName: 'test provider',
      ),
      throwsA(
        isA<AiPlanningException>().having(
          (error) => error.message,
          'message',
          contains('safe limit'),
        ),
      ),
    );
  });

  test('attaches response roots to a validated existing parent', () {
    const parentRequest = AiPlanningRequest(
      prompt: 'Add a garage floor epoxy plan under Home Maintenance.',
      boardName: 'Home',
      existingItems: [
        AiPlanningExistingItem(
          itemId: 'home-maintenance',
          title: 'Home Maintenance',
          type: WorkItemType.goal,
        ),
      ],
      placementMode: AiPlanningPlacementMode.existingParent,
      requestedParentItemId: 'home-maintenance',
      maxItems: 12,
    );

    final draft = parser.parse(
      '''
{"summary":"Extend home maintenance.","existingParentId":"home-maintenance","items":[{"id":"garage","title":"Epoxy garage floor","type":"project"},{"id":"prep","title":"Prepare concrete","type":"task","parentId":"garage"}]}
''',
      request: parentRequest,
      providerName: 'test provider',
    );

    expect(draft.existingParentItemId, 'home-maintenance');
    expect(draft.items, hasLength(2));
    expect(
        draft.items.any((item) => item.title == 'Home Maintenance'), isFalse);
  });

  test('normalizes a response root that directly names the existing parent',
      () {
    const parentRequest = AiPlanningRequest(
      prompt: 'Add a garage floor epoxy plan under Home Maintenance.',
      boardName: 'Home',
      existingItems: [
        AiPlanningExistingItem(
          itemId: 'home-maintenance',
          title: 'Home Maintenance',
          type: WorkItemType.goal,
        ),
      ],
      placementMode: AiPlanningPlacementMode.existingParent,
      requestedParentItemId: 'home-maintenance',
      maxItems: 12,
    );

    final draft = parser.parse(
      '''
{"summary":"Extend home maintenance.","existingParentId":"home-maintenance","items":[{"id":"garage","title":"Garage Floor Epoxy Coating","type":"project","parentId":"home-maintenance"},{"id":"prep","title":"Prepare concrete","type":"task","parentId":"garage"}]}
''',
      request: parentRequest,
      providerName: 'test provider',
    );

    expect(draft.existingParentItemId, 'home-maintenance');
    expect(draft.items.first.parentDraftId, isNull);
    expect(draft.items.last.parentDraftId, 'garage');
  });

  test('rejects duplicated existing titles and invalid external hierarchy', () {
    const parentRequest = AiPlanningRequest(
      prompt: 'Add a garage floor epoxy plan under Home Maintenance.',
      boardName: 'Home',
      existingItems: [
        AiPlanningExistingItem(
          itemId: 'home-maintenance',
          title: 'Home Maintenance',
          type: WorkItemType.goal,
        ),
      ],
      placementMode: AiPlanningPlacementMode.existingParent,
      requestedParentItemId: 'home-maintenance',
      maxItems: 12,
    );

    expect(
      () => parser.parse(
        '''
{"summary":"Duplicate.","items":[{"id":"home","title":"Home Maintenance","type":"goal"}]}
''',
        request: parentRequest,
        providerName: 'test provider',
      ),
      throwsA(
        isA<AiPlanningException>().having(
          (error) => error.message,
          'message',
          contains('duplicated the existing item'),
        ),
      ),
    );
  });
}
