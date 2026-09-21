import '../../board/domain/models/work_item_type.dart';

class AiPlanningRequest {
  const AiPlanningRequest({
    required this.prompt,
    required this.boardName,
    this.existingItems = const <AiPlanningExistingItem>[],
    this.placementMode = AiPlanningPlacementMode.automatic,
    this.requestedParentItemId,
    this.hierarchyPreference = AiPlanningHierarchyPreference.complete,
    this.maxItems = 32,
  });

  final String prompt;
  final String boardName;
  final List<AiPlanningExistingItem> existingItems;
  final AiPlanningPlacementMode placementMode;
  final String? requestedParentItemId;
  final AiPlanningHierarchyPreference hierarchyPreference;
  final int maxItems;
}

enum AiPlanningPlacementMode { automatic, topLevel, existingParent }

enum AiPlanningHierarchyPreference { complete, compact }

class AiPlanningExistingItem {
  const AiPlanningExistingItem({
    required this.itemId,
    required this.title,
    required this.type,
    this.parentItemId,
  });

  final String itemId;
  final String title;
  final WorkItemType type;
  final String? parentItemId;
}

class AiPlanningDraft {
  const AiPlanningDraft({
    required this.prompt,
    required this.summary,
    required this.items,
    required this.providerName,
    required this.createdAt,
    this.existingParentItemId,
  });

  final String prompt;
  final String summary;
  final List<AiPlanningDraftItem> items;
  final String providerName;
  final DateTime createdAt;
  final String? existingParentItemId;

  AiPlanningDraft copyWith({
    String? summary,
    List<AiPlanningDraftItem>? items,
  }) {
    return AiPlanningDraft(
      prompt: prompt,
      summary: summary ?? this.summary,
      items: items ?? this.items,
      providerName: providerName,
      createdAt: createdAt,
      existingParentItemId: existingParentItemId,
    );
  }
}

class AiPlanningDraftItem {
  const AiPlanningDraftItem({
    required this.draftId,
    required this.title,
    required this.type,
    this.parentDraftId,
    this.description,
    this.tags = const <String>[],
    this.estimatedEffortMinutes,
  });

  final String draftId;
  final String title;
  final WorkItemType type;
  final String? parentDraftId;
  final String? description;
  final List<String> tags;
  final int? estimatedEffortMinutes;

  AiPlanningDraftItem copyWith({
    String? title,
    WorkItemType? type,
    String? parentDraftId,
    String? description,
    List<String>? tags,
    int? estimatedEffortMinutes,
    bool clearParent = false,
    bool clearDescription = false,
    bool clearEstimatedEffort = false,
  }) {
    return AiPlanningDraftItem(
      draftId: draftId,
      title: title ?? this.title,
      type: type ?? this.type,
      parentDraftId: clearParent ? null : (parentDraftId ?? this.parentDraftId),
      description: clearDescription ? null : (description ?? this.description),
      tags: tags ?? this.tags,
      estimatedEffortMinutes: clearEstimatedEffort
          ? null
          : (estimatedEffortMinutes ?? this.estimatedEffortMinutes),
    );
  }
}

class AiPlanningException implements Exception {
  const AiPlanningException(this.message);

  final String message;

  @override
  String toString() => message;
}
