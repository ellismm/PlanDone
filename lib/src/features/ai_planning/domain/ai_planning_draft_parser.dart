import 'dart:convert';

import '../../board/domain/models/work_item_type.dart';
import 'ai_planning_draft.dart';

class AiPlanningDraftParser {
  const AiPlanningDraftParser();

  static const int maxPromptLength = 2000;
  static const int maxTitleLength = 160;
  static const int maxDescriptionLength = 1200;
  static const int maxSummaryLength = 500;
  static const int maxTagLength = 32;
  static const int maxTagsPerItem = 8;
  static const int maxEffortMinutes = 100000;

  AiPlanningDraft parse(
    String raw, {
    required AiPlanningRequest request,
    required String providerName,
    DateTime? createdAt,
  }) {
    validateRequest(request);
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const AiPlanningException(
        'The AI response was not valid JSON. Nothing was added to the board.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiPlanningException(
        'The AI response must be one JSON object. Nothing was added to the board.',
      );
    }
    _rejectUnknownKeys(
      decoded,
      const {'summary', 'existingParentId', 'items'},
      'response',
    );

    final summary = _requiredString(decoded, 'summary', maxSummaryLength);
    final rawItems = decoded['items'];
    if (rawItems is! List) {
      throw const AiPlanningException('AI response items must be a list.');
    }
    if (rawItems.isEmpty) {
      throw const AiPlanningException('The AI response did not contain items.');
    }
    if (rawItems.length > request.maxItems) {
      throw AiPlanningException(
        'The AI proposed ${rawItems.length} items; the safe limit is ${request.maxItems}.',
      );
    }

    final items = <AiPlanningDraftItem>[];
    for (var index = 0; index < rawItems.length; index += 1) {
      final rawItem = rawItems[index];
      if (rawItem is! Map) {
        throw AiPlanningException('AI item ${index + 1} must be an object.');
      }
      final item = rawItem.cast<String, dynamic>();
      _rejectUnknownKeys(
        item,
        const {
          'id',
          'title',
          'type',
          'parentId',
          'description',
          'tags',
          'estimatedEffortMinutes',
        },
        'item ${index + 1}',
      );
      final id = _requiredString(item, 'id', 40);
      if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
        throw AiPlanningException(
          'AI item ${index + 1} has an invalid id. Use letters, numbers, dashes, or underscores.',
        );
      }
      final typeName = _requiredString(item, 'type', 16).toLowerCase();
      final type = WorkItemType.values
          .where((candidate) => candidate.name == typeName)
          .cast<WorkItemType?>()
          .firstWhere((_) => true, orElse: () => null);
      if (type == null) {
        throw AiPlanningException(
          'AI item "$id" has unsupported type "$typeName".',
        );
      }
      final parentId = _optionalString(item, 'parentId', 40);
      final description =
          _optionalString(item, 'description', maxDescriptionLength);
      final tags = _readTags(item['tags'], itemId: id);
      final effort = _readEffort(item['estimatedEffortMinutes'], itemId: id);
      items.add(
        AiPlanningDraftItem(
          draftId: id,
          title: _requiredString(item, 'title', maxTitleLength),
          type: type,
          parentDraftId: parentId,
          description: description,
          tags: tags,
          estimatedEffortMinutes: effort,
        ),
      );
    }

    final existingParentItemId = _resolveExistingParentId(
      decoded,
      request: request,
    );
    final normalizedItems = _normalizeExistingParentReferences(
      items,
      existingParentItemId: existingParentItemId,
    );
    _validateAgainstExistingItems(
      normalizedItems,
      existingParentItemId: existingParentItemId,
      request: request,
    );

    final draft = AiPlanningDraft(
      prompt: request.prompt.trim(),
      summary: summary,
      items: List.unmodifiable(normalizedItems),
      providerName: providerName,
      createdAt: createdAt ?? DateTime.now(),
      existingParentItemId: existingParentItemId,
    );
    validateDraft(draft, maxItems: request.maxItems);
    return draft;
  }

  static List<AiPlanningDraftItem> _normalizeExistingParentReferences(
    List<AiPlanningDraftItem> items, {
    required String? existingParentItemId,
  }) {
    if (existingParentItemId == null) return items;
    return [
      for (final item in items)
        if (item.parentDraftId == existingParentItemId)
          item.copyWith(clearParent: true)
        else
          item,
    ];
  }

  void validateRequest(AiPlanningRequest request) {
    final prompt = request.prompt.trim();
    if (prompt.length < 10) {
      throw const AiPlanningException(
        'Describe the outcome in at least 10 characters.',
      );
    }
    if (prompt.length > maxPromptLength) {
      throw const AiPlanningException(
        'The planning prompt must be 2,000 characters or fewer.',
      );
    }
    if (request.maxItems < 1 || request.maxItems > 64) {
      throw const AiPlanningException('The requested item limit is unsafe.');
    }
    final existingIds = <String>{};
    for (final item in request.existingItems) {
      if (item.itemId.trim().isEmpty || !existingIds.add(item.itemId)) {
        throw const AiPlanningException(
          'Existing planning item ids must be non-empty and unique.',
        );
      }
      if (item.title.trim().isEmpty ||
          item.title.trim().length > maxTitleLength) {
        throw const AiPlanningException(
          'An existing planning item has an invalid title.',
        );
      }
    }
    if (request.placementMode == AiPlanningPlacementMode.existingParent) {
      final requestedParentId = request.requestedParentItemId;
      if (requestedParentId == null ||
          !existingIds.contains(requestedParentId)) {
        throw const AiPlanningException(
          'Choose a valid existing parent before generating the draft.',
        );
      }
    } else if (request.requestedParentItemId != null) {
      throw const AiPlanningException(
        'An existing parent can only be set for existing-parent placement.',
      );
    }
  }

  void validateDraft(AiPlanningDraft draft, {int maxItems = 32}) {
    if (draft.items.isEmpty) {
      throw const AiPlanningException('A planning draft must contain items.');
    }
    if (draft.items.length > maxItems) {
      throw AiPlanningException(
        'The draft contains more than the $maxItems item limit.',
      );
    }

    final byId = <String, AiPlanningDraftItem>{};
    for (final item in draft.items) {
      final id = item.draftId.trim();
      if (id.isEmpty || byId.containsKey(id)) {
        throw AiPlanningException(
            'Draft item ids must be non-empty and unique.');
      }
      if (item.title.trim().isEmpty ||
          item.title.trim().length > maxTitleLength) {
        throw AiPlanningException('Draft item "$id" has an invalid title.');
      }
      byId[id] = item;
    }

    for (final item in draft.items) {
      final parentId = item.parentDraftId;
      if (parentId == null) continue;
      final parent = byId[parentId];
      if (parent == null) {
        throw AiPlanningException(
          'Draft item "${item.title}" references a missing parent.',
        );
      }
      if (_typeRank(parent.type) >= _typeRank(item.type)) {
        throw AiPlanningException(
          'The parent of "${item.title}" must be a higher-level item.',
        );
      }
    }

    final visiting = <String>{};
    final visited = <String>{};
    void visit(String id) {
      if (visited.contains(id)) return;
      if (!visiting.add(id)) {
        throw const AiPlanningException(
          'The AI draft contains a hierarchy cycle.',
        );
      }
      final parentId = byId[id]!.parentDraftId;
      if (parentId != null) visit(parentId);
      visiting.remove(id);
      visited.add(id);
    }

    for (final id in byId.keys) {
      visit(id);
    }
  }

  List<AiPlanningDraftItem> topologicalItems(AiPlanningDraft draft) {
    validateDraft(draft, maxItems: 64);
    final remaining = [...draft.items];
    final inserted = <String>{};
    final ordered = <AiPlanningDraftItem>[];
    while (remaining.isNotEmpty) {
      final index = remaining.indexWhere(
        (item) =>
            item.parentDraftId == null || inserted.contains(item.parentDraftId),
      );
      if (index < 0) {
        throw const AiPlanningException(
          'The draft hierarchy could not be ordered safely.',
        );
      }
      final item = remaining.removeAt(index);
      ordered.add(item);
      inserted.add(item.draftId);
    }
    return ordered;
  }

  static String? _resolveExistingParentId(
    Map<String, dynamic> response, {
    required AiPlanningRequest request,
  }) {
    final responseParentId = _optionalString(response, 'existingParentId', 200);
    switch (request.placementMode) {
      case AiPlanningPlacementMode.topLevel:
        if (responseParentId != null) {
          throw const AiPlanningException(
            'The AI selected an existing parent for a top-level plan.',
          );
        }
        return null;
      case AiPlanningPlacementMode.existingParent:
        final requestedParentId = request.requestedParentItemId!;
        if (responseParentId != null && responseParentId != requestedParentId) {
          throw const AiPlanningException(
            'The AI changed the existing parent selected by the user.',
          );
        }
        return requestedParentId;
      case AiPlanningPlacementMode.automatic:
        if (responseParentId == null) return null;
        if (!request.existingItems
            .any((item) => item.itemId == responseParentId)) {
          throw const AiPlanningException(
            'The AI selected an existing parent that is not on this board.',
          );
        }
        return responseParentId;
    }
  }

  static void _validateAgainstExistingItems(
    List<AiPlanningDraftItem> items, {
    required String? existingParentItemId,
    required AiPlanningRequest request,
  }) {
    final existingById = {
      for (final item in request.existingItems) item.itemId: item,
    };
    final normalizedExistingTitles = {
      for (final item in request.existingItems) _normalizedTitle(item.title),
    };
    final duplicate = items
        .where(
          (item) => normalizedExistingTitles.contains(
            _normalizedTitle(item.title),
          ),
        )
        .cast<AiPlanningDraftItem?>()
        .firstWhere((_) => true, orElse: () => null);
    if (duplicate != null) {
      throw AiPlanningException(
        'The AI duplicated the existing item "${duplicate.title}". Regenerate or choose that item as the parent instead.',
      );
    }
    if (existingParentItemId == null) return;
    final parent = existingById[existingParentItemId];
    if (parent == null) {
      throw const AiPlanningException(
        'The selected existing parent is no longer available.',
      );
    }
    if (parent.type == WorkItemType.action) {
      throw const AiPlanningException(
        'Actions cannot contain generated children.',
      );
    }
    for (final root in items.where((item) => item.parentDraftId == null)) {
      if (_typeRank(parent.type) >= _typeRank(root.type)) {
        throw AiPlanningException(
          'Generated item "${root.title}" must be below the selected ${parent.type.name} "${parent.title}".',
        );
      }
    }
  }

  static String _normalizedTitle(String title) =>
      title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static List<String> _readTags(Object? value, {required String itemId}) {
    if (value == null) return const <String>[];
    if (value is! List || value.length > maxTagsPerItem) {
      throw AiPlanningException('AI item "$itemId" has invalid tags.');
    }
    final tags = <String>[];
    for (final rawTag in value) {
      if (rawTag is! String ||
          rawTag.trim().isEmpty ||
          rawTag.trim().length > maxTagLength) {
        throw AiPlanningException('AI item "$itemId" has an invalid tag.');
      }
      final normalized = rawTag.trim().toLowerCase();
      if (!tags.contains(normalized)) tags.add(normalized);
    }
    return List.unmodifiable(tags);
  }

  static int? _readEffort(Object? value, {required String itemId}) {
    if (value == null) return null;
    if (value is! num || value != value.roundToDouble()) {
      throw AiPlanningException(
        'AI item "$itemId" has invalid estimated effort.',
      );
    }
    final effort = value.toInt();
    if (effort < 1 || effort > maxEffortMinutes) {
      throw AiPlanningException(
        'AI item "$itemId" has estimated effort outside the safe range.',
      );
    }
    return effort;
  }

  static String _requiredString(
    Map<String, dynamic> object,
    String key,
    int maxLength,
  ) {
    final value = object[key];
    if (value is! String || value.trim().isEmpty) {
      throw AiPlanningException('AI response field "$key" is required.');
    }
    final normalized = value.trim();
    if (normalized.length > maxLength) {
      throw AiPlanningException('AI response field "$key" is too long.');
    }
    return normalized;
  }

  static String? _optionalString(
    Map<String, dynamic> object,
    String key,
    int maxLength,
  ) {
    final value = object[key];
    if (value == null) return null;
    if (value is! String) {
      throw AiPlanningException('AI response field "$key" must be text.');
    }
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    if (normalized.length > maxLength) {
      throw AiPlanningException('AI response field "$key" is too long.');
    }
    return normalized;
  }

  static void _rejectUnknownKeys(
    Map<String, dynamic> object,
    Set<String> allowed,
    String label,
  ) {
    final unknown = object.keys.where((key) => !allowed.contains(key)).toList();
    if (unknown.isNotEmpty) {
      throw AiPlanningException(
        'The AI $label contained unsupported fields: ${unknown.join(', ')}.',
      );
    }
  }

  static int _typeRank(WorkItemType type) => WorkItemType.values.indexOf(type);
}
