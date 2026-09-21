import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app_routes.dart';
import '../../board/domain/models/board_snapshot.dart';
import '../../board/domain/models/work_item.dart';
import '../../board/domain/models/work_item_type.dart';
import '../../board/presentation/board_controller.dart';
import '../../board/presentation/hierarchy_visuals.dart';
import '../domain/ai_planning_draft.dart';
import '../domain/ai_planning_draft_ordering.dart';
import '../domain/ai_planning_draft_parser.dart';
import '../domain/ai_planning_parent_matcher.dart';
import 'ai_planning_controller.dart';

class AiPlanningPage extends ConsumerStatefulWidget {
  const AiPlanningPage({super.key});

  @override
  ConsumerState<AiPlanningPage> createState() => _AiPlanningPageState();
}

class _AiPlanningPageState extends ConsumerState<AiPlanningPage> {
  static const _automaticPlacement = '__automatic__';
  static const _topLevelPlacement = '__top_level__';

  final _promptController = TextEditingController();
  final _parser = const AiPlanningDraftParser();
  AiPlanningDraft? _draft;
  String? _error;
  bool _isGenerating = false;
  bool _isApproving = false;
  int _maxItems = 24;
  String _placement = _automaticPlacement;
  AiPlanningHierarchyPreference _hierarchyPreference =
      AiPlanningHierarchyPreference.complete;

  @override
  void dispose() {
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _generate(BoardSnapshot snapshot) async {
    final provider = ref.read(aiPlanningProviderProvider);
    final existingItems = snapshot.items
        .where((item) => !item.archived && !item.isInbox)
        .map(
          (item) => AiPlanningExistingItem(
            itemId: item.itemId,
            title: item.title,
            type: item.type,
            parentItemId: item.parentId,
          ),
        )
        .toList();
    final explicitParentId = _resolvedParentId(snapshot);
    final placementMode = _placement == _topLevelPlacement
        ? AiPlanningPlacementMode.topLevel
        : explicitParentId == null
            ? AiPlanningPlacementMode.automatic
            : AiPlanningPlacementMode.existingParent;
    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      final draft = await provider.generate(
        AiPlanningRequest(
          prompt: _promptController.text,
          boardName: snapshot.board.name,
          existingItems: existingItems,
          placementMode: placementMode,
          requestedParentItemId: explicitParentId,
          hierarchyPreference: _hierarchyPreference,
          maxItems: _maxItems,
        ),
      );
      if (!mounted) return;
      setState(() => _draft = draft);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _approve(BoardSnapshot snapshot) async {
    final draft = _draft;
    if (draft == null) return;
    try {
      _parser.validateDraft(draft, maxItems: 64);
    } catch (error) {
      setState(() => _error = _messageFor(error));
      return;
    }

    final existingParent = _existingParentForDraft(draft, snapshot);
    final destination = existingParent == null
        ? 'as a new top-level hierarchy in "${snapshot.board.name}"'
        : 'under the existing ${_typeLabel(existingParent.type).toLowerCase()} "${existingParent.title}"';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add approved plan?'),
        content: Text(
          'Create ${draft.items.length} reviewed item(s) $destination? This is the first point where the AI draft can change board data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep reviewing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Approve and add'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isApproving = true;
      _error = null;
    });
    try {
      final result = await ref.read(aiPlanningCommitServiceProvider).commit(
            draft: draft,
            snapshot: snapshot,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Added ${result.createdItems.length} reviewed AI-assisted items.',
          ),
        ),
      );
      Navigator.of(context).pushReplacementNamed(AppRoutes.workspace);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _messageFor(error));
    } finally {
      if (mounted) setState(() => _isApproving = false);
    }
  }

  List<WorkItem> _eligibleParents(BoardSnapshot snapshot) {
    final items = snapshot.items
        .where(
          (item) =>
              !item.archived &&
              !item.isInbox &&
              item.type != WorkItemType.action,
        )
        .toList();
    items.sort((a, b) {
      final typeCompare = WorkItemType.values
          .indexOf(a.type)
          .compareTo(WorkItemType.values.indexOf(b.type));
      return typeCompare != 0
          ? typeCompare
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return items;
  }

  String? _resolvedParentId(BoardSnapshot snapshot) {
    if (_placement != _automaticPlacement && _placement != _topLevelPlacement) {
      return _placement;
    }
    if (_placement == _topLevelPlacement) return null;

    return AiPlanningParentMatcher.bestParentId(
      prompt: _promptController.text,
      items: _eligibleParents(snapshot).map(
        (item) => AiPlanningExistingItem(
          itemId: item.itemId,
          title: item.title,
          type: item.type,
          parentItemId: item.parentId,
        ),
      ),
    );
  }

  WorkItem? _automaticMatchedParent(BoardSnapshot snapshot) {
    if (_placement != _automaticPlacement) return null;
    final parentId = _resolvedParentId(snapshot);
    if (parentId == null) return null;
    return snapshot.items
        .where((item) => item.itemId == parentId)
        .cast<WorkItem?>()
        .firstWhere((_) => true, orElse: () => null);
  }

  static WorkItem? _existingParentForDraft(
    AiPlanningDraft draft,
    BoardSnapshot snapshot,
  ) {
    final parentId = draft.existingParentItemId;
    if (parentId == null) return null;
    return snapshot.items
        .where((item) => item.itemId == parentId)
        .cast<WorkItem?>()
        .firstWhere((_) => true, orElse: () => null);
  }

  static Color? _existingBranchColor(
    BoardSnapshot snapshot,
    WorkItem? existingParent,
  ) {
    if (existingParent == null ||
        !snapshot.board.validationSettings.hierarchyColorGroupingByGoal) {
      return null;
    }
    final byId = {for (final item in snapshot.items) item.itemId: item};
    final goalId = topLevelGoalIdForItem(existingParent, byId);
    if (goalId == null) return null;
    final colors = resolveGoalColors(
      items: snapshot.items,
      overrides: snapshot.board.validationSettings.hierarchyGoalColorOverrides,
    );
    final colorValue = colors[goalId];
    return colorValue == null ? null : Color(colorValue);
  }

  Future<void> _rejectDraft() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject this draft?'),
        content: const Text(
          'Discard the generated proposal? No board items have been created.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reject draft'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      setState(() {
        _draft = null;
        _error = null;
      });
    }
  }

  void _removeItem(AiPlanningDraftItem item) {
    final draft = _draft;
    if (draft == null) return;
    final items = draft.items
        .where((candidate) => candidate.draftId != item.draftId)
        .map(
          (candidate) => candidate.parentDraftId == item.draftId
              ? candidate.copyWith(clearParent: true)
              : candidate,
        )
        .toList();
    setState(() {
      _draft = items.isEmpty
          ? null
          : draft.copyWith(items: List.unmodifiable(items));
      _error = null;
    });
  }

  Future<void> _editItem(AiPlanningDraftItem item) async {
    final draft = _draft;
    if (draft == null) return;
    final updated = await showDialog<AiPlanningDraftItem>(
      context: context,
      builder: (context) => _AiDraftItemEditor(
        item: item,
        allItems: draft.items,
      ),
    );
    if (updated == null || !mounted) return;
    final items = [
      for (final candidate in draft.items)
        if (candidate.draftId == updated.draftId) updated else candidate,
    ];
    final nextDraft = draft.copyWith(items: List.unmodifiable(items));
    try {
      _parser.validateDraft(nextDraft, maxItems: 64);
      setState(() {
        _draft = nextDraft;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = _messageFor(error));
    }
  }

  void _moveItem(AiPlanningDraftItem item, {required bool moveUp}) {
    final draft = _draft;
    if (draft == null) return;
    final nextDraft = moveUp
        ? AiPlanningDraftOrdering.moveUp(draft, item.draftId)
        : AiPlanningDraftOrdering.moveDown(draft, item.draftId);
    if (identical(nextDraft, draft)) return;
    try {
      _parser.validateDraft(nextDraft, maxItems: 64);
      setState(() {
        _draft = nextDraft;
        _error = null;
      });
    } catch (error) {
      setState(() => _error = _messageFor(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(boardStreamProvider);
    final provider = ref.watch(aiPlanningProviderProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Plan with AI'),
        actions: [
          if (_draft != null)
            TextButton(
              onPressed: _isApproving ? null : _rejectDraft,
              child: const Text('Reject'),
            ),
        ],
      ),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Unable to load board: $error')),
        data: (snapshot) {
          final automaticParent = _automaticMatchedParent(snapshot);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SafetyNotice(providerName: provider.displayName),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('ai-planning-prompt'),
                controller: _promptController,
                enabled: !_isGenerating && !_isApproving,
                minLines: 4,
                maxLines: 8,
                maxLength: AiPlanningDraftParser.maxPromptLength,
                decoration: const InputDecoration(
                  labelText: 'What outcome do you want to plan?',
                  hintText:
                      'Example: Prepare for a two-week family trip without missing work or home responsibilities.',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {
                  _draft = null;
                  _error = null;
                }),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: const ValueKey('ai-planning-placement'),
                initialValue: _placement,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Place generated plan under',
                  helperText: automaticParent == null
                      ? 'Automatic recognizes an existing item named in your prompt.'
                      : 'Matched ${_typeLabel(automaticParent.type)} • ${automaticParent.title}',
                  helperMaxLines: 2,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: _automaticPlacement,
                    child: Text('Automatic — match the prompt'),
                  ),
                  const DropdownMenuItem(
                    value: _topLevelPlacement,
                    child: Text('New top-level hierarchy'),
                  ),
                  for (final item in _eligibleParents(snapshot))
                    DropdownMenuItem(
                      value: item.itemId,
                      child: Text(
                        '${_typeLabel(item.type)} • ${item.title}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _isGenerating || _isApproving
                    ? null
                    : (value) => setState(() {
                          _placement = value ?? _automaticPlacement;
                          _draft = null;
                          _error = null;
                        }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AiPlanningHierarchyPreference>(
                key: const ValueKey('ai-planning-hierarchy-preference'),
                initialValue: _hierarchyPreference,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Hierarchy detail',
                  helperText:
                      'Full uses every meaningful level; compact may skip levels.',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: AiPlanningHierarchyPreference.complete,
                    child: Text('Full • Goal → Project → Task → Action'),
                  ),
                  DropdownMenuItem(
                    value: AiPlanningHierarchyPreference.compact,
                    child: Text('Compact • skip unnecessary levels'),
                  ),
                ],
                onChanged: _isGenerating || _isApproving
                    ? null
                    : (value) => setState(() {
                          _hierarchyPreference =
                              value ?? AiPlanningHierarchyPreference.complete;
                          _draft = null;
                          _error = null;
                        }),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final sizePicker = DropdownButtonFormField<int>(
                    initialValue: _maxItems,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Draft size limit',
                      border: OutlineInputBorder(),
                    ),
                    items: const [12, 24, 32]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('Up to $value items'),
                          ),
                        )
                        .toList(),
                    onChanged: _isGenerating
                        ? null
                        : (value) => setState(() => _maxItems = value ?? 24),
                  );
                  final generateButton = FilledButton.icon(
                    key: const ValueKey('generate-ai-plan'),
                    onPressed: provider.isAvailable && !_isGenerating
                        ? () => _generate(snapshot)
                        : null,
                    icon: _isGenerating
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome),
                    label: Text(_isGenerating ? 'Generating...' : 'Generate'),
                  );
                  if (constraints.maxWidth < 480) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        sizePicker,
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: generateButton,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: sizePicker),
                      const SizedBox(width: 12),
                      generateButton,
                    ],
                  );
                },
              ),
              if (!provider.isAvailable) ...[
                const SizedBox(height: 12),
                const _MessageCard(
                  message:
                      'AI generation is off in this build. Enable Firebase AI Logic, App Check, and USE_FIREBASE_AI before distributing the feature.',
                  icon: Icons.settings_suggest_outlined,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _MessageCard(
                  message: _error!,
                  icon: Icons.error_outline,
                  isError: true,
                ),
              ],
              if (_draft != null) ...[
                const SizedBox(height: 24),
                _DraftReviewHeader(
                  draft: _draft!,
                  existingParent: _existingParentForDraft(_draft!, snapshot),
                ),
                const SizedBox(height: 8),
                _DraftHierarchy(
                  draft: _draft!,
                  existingParent: _existingParentForDraft(_draft!, snapshot),
                  accentColor: _existingBranchColor(
                    snapshot,
                    _existingParentForDraft(_draft!, snapshot),
                  ),
                  enabled: !_isApproving,
                  onEdit: _editItem,
                  onRemove: _removeItem,
                  onMoveUp: (item) => _moveItem(item, moveUp: true),
                  onMoveDown: (item) => _moveItem(item, moveUp: false),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('approve-ai-plan'),
                  onPressed: _isApproving ? null : () => _approve(snapshot),
                  icon: _isApproving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _isApproving
                        ? 'Adding approved items...'
                        : 'Approve and add ${_draft!.items.length} items',
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static String _messageFor(Object error) {
    if (error is AiPlanningException) return error.message;
    return error.toString().replaceFirst('Exception: ', '');
  }
}

class _AiDraftItemEditor extends StatefulWidget {
  const _AiDraftItemEditor({required this.item, required this.allItems});

  final AiPlanningDraftItem item;
  final List<AiPlanningDraftItem> allItems;

  @override
  State<_AiDraftItemEditor> createState() => _AiDraftItemEditorState();
}

class _AiDraftItemEditorState extends State<_AiDraftItemEditor> {
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _effortController;
  late WorkItemType _type;
  String? _parentId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.item.title);
    _descriptionController =
        TextEditingController(text: widget.item.description ?? '');
    _effortController = TextEditingController(
      text: widget.item.estimatedEffortMinutes?.toString() ?? '',
    );
    _type = widget.item.type;
    _parentId = widget.item.parentDraftId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _effortController.dispose();
    super.dispose();
  }

  List<AiPlanningDraftItem> get _parentCandidates => widget.allItems
      .where(
        (candidate) =>
            candidate.draftId != widget.item.draftId &&
            WorkItemType.values.indexOf(candidate.type) <
                WorkItemType.values.indexOf(_type),
      )
      .toList();

  void _save() {
    final title = _titleController.text.trim();
    final effortText = _effortController.text.trim();
    final effort = effortText.isEmpty ? null : int.tryParse(effortText);
    if (title.isEmpty) {
      setState(() => _error = 'Title is required.');
      return;
    }
    if (effortText.isNotEmpty &&
        (effort == null ||
            effort < 1 ||
            effort > AiPlanningDraftParser.maxEffortMinutes)) {
      setState(() => _error = 'Estimated effort must be a positive number.');
      return;
    }
    Navigator.of(context).pop(
      widget.item.copyWith(
        title: title,
        type: _type,
        parentDraftId: _parentId,
        clearParent: _parentId == null,
        description: _descriptionController.text.trim(),
        clearDescription: _descriptionController.text.trim().isEmpty,
        estimatedEffortMinutes: effort,
        clearEstimatedEffort: effort == null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _parentCandidates;
    if (_parentId != null &&
        !candidates.any((item) => item.draftId == _parentId)) {
      _parentId = null;
    }
    return AlertDialog(
      title: const Text('Edit draft item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              maxLength: AiPlanningDraftParser.maxTitleLength,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            DropdownButtonFormField<WorkItemType>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: WorkItemType.values
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(_typeLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _type = value ?? _type),
            ),
            DropdownButtonFormField<String?>(
              initialValue: _parentId,
              decoration: const InputDecoration(labelText: 'Parent'),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('No parent'),
                ),
                for (final candidate in candidates)
                  DropdownMenuItem<String?>(
                    value: candidate.draftId,
                    child: Text(candidate.title),
                  ),
              ],
              onChanged: (value) => setState(() => _parentId = value),
            ),
            TextField(
              controller: _descriptionController,
              minLines: 2,
              maxLines: 4,
              maxLength: AiPlanningDraftParser.maxDescriptionLength,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            TextField(
              controller: _effortController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Estimated effort (minutes)',
              ),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save draft')),
      ],
    );
  }
}

class _DraftHierarchy extends StatefulWidget {
  const _DraftHierarchy({
    required this.draft,
    required this.existingParent,
    required this.accentColor,
    required this.enabled,
    required this.onEdit,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final AiPlanningDraft draft;
  final WorkItem? existingParent;
  final Color? accentColor;
  final bool enabled;
  final ValueChanged<AiPlanningDraftItem> onEdit;
  final ValueChanged<AiPlanningDraftItem> onRemove;
  final ValueChanged<AiPlanningDraftItem> onMoveUp;
  final ValueChanged<AiPlanningDraftItem> onMoveDown;

  @override
  State<_DraftHierarchy> createState() => _DraftHierarchyState();
}

class _DraftHierarchyState extends State<_DraftHierarchy> {
  final Set<String> _collapsedIds = <String>{};

  @override
  void didUpdateWidget(covariant _DraftHierarchy oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentIds = widget.draft.items.map((item) => item.draftId).toSet();
    _collapsedIds.removeWhere((id) => !currentIds.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    final childrenByParent = <String?, List<AiPlanningDraftItem>>{};
    for (final item in widget.draft.items) {
      childrenByParent.putIfAbsent(item.parentDraftId, () => []).add(item);
    }
    final rows = <Widget>[];

    void addBranch(AiPlanningDraftItem item, int depth) {
      final children = childrenByParent[item.draftId] ?? const [];
      final isCollapsed = _collapsedIds.contains(item.draftId);
      rows.add(
        _DraftHierarchyRow(
          key: ValueKey('ai-draft-tree-${item.draftId}'),
          item: item,
          depth: depth,
          childCount: children.length,
          isCollapsed: isCollapsed,
          accentColor: widget.accentColor,
          enabled: widget.enabled,
          canMoveUp:
              AiPlanningDraftOrdering.canMoveUp(widget.draft, item.draftId),
          canMoveDown:
              AiPlanningDraftOrdering.canMoveDown(widget.draft, item.draftId),
          onToggleCollapsed: children.isEmpty
              ? null
              : () => setState(() {
                    if (!_collapsedIds.add(item.draftId)) {
                      _collapsedIds.remove(item.draftId);
                    }
                  }),
          onEdit: () => widget.onEdit(item),
          onRemove: () => widget.onRemove(item),
          onMoveUp: () => widget.onMoveUp(item),
          onMoveDown: () => widget.onMoveDown(item),
        ),
      );
      if (isCollapsed) return;
      for (final child in children) {
        addBranch(child, depth + 1);
      }
    }

    if (widget.existingParent != null) {
      rows.add(
        _ExistingParentRow(
          item: widget.existingParent!,
          childCount: childrenByParent[null]?.length ?? 0,
          accentColor: widget.accentColor,
        ),
      );
    }
    final rootDepth = widget.existingParent == null ? 0 : 1;
    for (final root in childrenByParent[null] ?? const []) {
      addBranch(root, rootDepth);
    }

    return Semantics(
      container: true,
      label: 'AI draft hierarchy preview',
      child: Column(children: rows),
    );
  }
}

class _ExistingParentRow extends StatelessWidget {
  const _ExistingParentRow({
    required this.item,
    required this.childCount,
    required this.accentColor,
  });

  final WorkItem item;
  final int childCount;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return _DraftPreviewCard(
      key: const ValueKey('ai-existing-parent-context'),
      title: item.title,
      type: item.type,
      childCount: childCount,
      accentColor: accentColor,
      accentKey: 'existing-${item.itemId}',
      badge: 'EXISTING',
    );
  }
}

class _DraftHierarchyRow extends StatelessWidget {
  const _DraftHierarchyRow({
    super.key,
    required this.item,
    required this.depth,
    required this.childCount,
    required this.isCollapsed,
    required this.accentColor,
    required this.enabled,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onToggleCollapsed,
    required this.onEdit,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final AiPlanningDraftItem item;
  final int depth;
  final int childCount;
  final bool isCollapsed;
  final Color? accentColor;
  final bool enabled;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback? onToggleCollapsed;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (depth > 0) ...[
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: SizedBox(
                  width: depth * 10.0 + 12,
                  child: CustomPaint(
                    painter: _DraftHierarchyGuidePainter(
                      depth: depth,
                      color: (accentColor ??
                              Theme.of(context).colorScheme.outlineVariant)
                          .withValues(alpha: 0.55),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              SizedBox(
                width: 22,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: onToggleCollapsed == null
                      ? const SizedBox.shrink()
                      : Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: InkWell(
                            onTap: onToggleCollapsed,
                            borderRadius: BorderRadius.circular(10),
                            child: Icon(
                              isCollapsed
                                  ? Icons.chevron_right
                                  : Icons.expand_more,
                              size: 18,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                ),
              ),
            ],
            Expanded(
              child: _DraftPreviewCard(
                title: item.title,
                type: item.type,
                childCount: childCount,
                description: item.description,
                effortMinutes: item.estimatedEffortMinutes,
                accentColor: accentColor,
                accentKey: item.draftId,
                onTap: enabled ? onEdit : null,
                actions: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: ValueKey('ai-draft-move-up-${item.draftId}'),
                      tooltip: 'Move ${item.title} up',
                      visualDensity: VisualDensity.compact,
                      onPressed: enabled && canMoveUp ? onMoveUp : null,
                      icon: const Icon(Icons.arrow_upward, size: 18),
                    ),
                    IconButton(
                      key: ValueKey('ai-draft-move-down-${item.draftId}'),
                      tooltip: 'Move ${item.title} down',
                      visualDensity: VisualDensity.compact,
                      onPressed: enabled && canMoveDown ? onMoveDown : null,
                      icon: const Icon(Icons.arrow_downward, size: 18),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Draft item actions',
                      enabled: enabled,
                      iconSize: 18,
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'edit') onEdit();
                        if (value == 'remove') onRemove();
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit draft item'),
                        ),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text('Remove draft item'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftPreviewCard extends StatelessWidget {
  const _DraftPreviewCard({
    super.key,
    required this.title,
    required this.type,
    required this.childCount,
    this.description,
    this.effortMinutes,
    this.accentColor,
    this.accentKey,
    this.badge,
    this.onTap,
    this.actions,
  });

  final String title;
  final WorkItemType type;
  final int childCount;
  final String? description;
  final int? effortMinutes;
  final Color? accentColor;
  final String? accentKey;
  final String? badge;
  final VoidCallback? onTap;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (accentColor != null)
                  Container(
                    key: ValueKey('ai-draft-accent-${accentKey ?? title}'),
                    width: 4,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (description?.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          description!.trim(),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              type.name.toUpperCase(),
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (childCount > 0)
                              Text(
                                'Children: $childCount',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (effortMinutes != null)
                              Text(
                                '$effortMinutes min',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (badge != null)
                              Text(
                                badge!,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color:
                                      accentColor ?? theme.colorScheme.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (actions != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: actions,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DraftHierarchyGuidePainter extends CustomPainter {
  const _DraftHierarchyGuidePainter({
    required this.depth,
    required this.color,
  });

  final int depth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < depth; i++) {
      final x = (i * 10.0) + 5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    final connectorStartX = ((depth - 1) * 10.0) + 5;
    final midY = size.height * 0.5;
    canvas.drawLine(
      Offset(connectorStartX, midY),
      Offset(size.width, midY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DraftHierarchyGuidePainter oldDelegate) =>
      oldDelegate.depth != depth || oldDelegate.color != color;
}

class _SafetyNotice extends StatelessWidget {
  const _SafetyNotice({required this.providerName});

  final String providerName;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Human-controlled planning',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Generate sends your prompt, board name, and up to 80 current item titles, types, and IDs to $providerName so it can extend an existing branch without duplicating it. The response stays an editable in-memory draft. PlanDone writes nothing until you explicitly approve it.',
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftReviewHeader extends StatelessWidget {
  const _DraftReviewHeader({required this.draft, required this.existingParent});

  final AiPlanningDraft draft;
  final WorkItem? existingParent;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review before approval',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(draft.summary),
        const SizedBox(height: 4),
        Text(
          '${draft.items.length} staged items • ${draft.providerName}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          existingParent == null
              ? 'Placement: new top-level hierarchy'
              : 'Placement: children of existing ${_typeLabel(existingParent!.type).toLowerCase()} "${existingParent!.title}"',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 4),
        Text(
          'Use the arrows to reorder siblings. Tap a card to edit or reparent it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.message,
    required this.icon,
    this.isError = false,
  });

  final String message;
  final IconData icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.errorContainer
        : Theme.of(context).colorScheme.secondaryContainer;
    return Card(
      color: color,
      child: ListTile(leading: Icon(icon), title: Text(message)),
    );
  }
}

String _typeLabel(WorkItemType type) => switch (type) {
      WorkItemType.goal => 'Goal',
      WorkItemType.project => 'Project',
      WorkItemType.task => 'Task',
      WorkItemType.action => 'Action',
    };
