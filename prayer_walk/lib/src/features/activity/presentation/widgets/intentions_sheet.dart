import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_spacing.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/widgets.dart';
import '../../data/activity_providers.dart';
import '../../domain/activity.dart';

/// Choose what you are carrying on this walk.
///
/// Returns the chosen intentions, or null if dismissed.
Future<List<PrayerIntention>?> showIntentionsSheet(
  BuildContext context, {
  required List<PrayerIntention> initial,
}) {
  return showModalBottomSheet<List<PrayerIntention>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _IntentionsSheet(initial: initial),
  );
}

class _IntentionsSheet extends ConsumerStatefulWidget {
  const _IntentionsSheet({required this.initial});

  final List<PrayerIntention> initial;

  @override
  ConsumerState<_IntentionsSheet> createState() => _IntentionsSheetState();
}

class _IntentionsSheetState extends ConsumerState<_IntentionsSheet> {
  late List<PrayerIntention> _chosen = List.of(widget.initial);
  final _field = TextEditingController();
  PrayerCategory _category = PrayerCategory.family;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _toggle(PrayerIntention intention) {
    setState(() {
      final index = _chosen.indexWhere((i) => i.id == intention.id);
      if (index >= 0) {
        _chosen.removeAt(index);
      } else {
        _chosen = [..._chosen, intention];
      }
    });
  }

  void _addCustom() {
    final text = _field.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _chosen = [
        ..._chosen,
        PrayerIntention(
          id: 'i_local_${DateTime.now().microsecondsSinceEpoch}',
          text: text,
          category: _category,
          createdAt: DateTime.now(),
        ),
      ];
      _field.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = ref.watch(suggestedIntentionsProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, scrollController) => Column(
        children: [
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              children: [
                Text('What are you carrying?', style: theme.textTheme.displaySmall),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Name it now and it stays with the walk. You can add more '
                  'when you finish.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                if (_chosen.isNotEmpty) ...[
                  const SectionHeader(title: 'Carrying', dense: true),
                  for (final intention in _chosen)
                    _ChosenRow(
                      intention: intention,
                      onRemove: () => setState(
                        () => _chosen = _chosen
                            .where((i) => i.id != intention.id)
                            .toList(),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.xl),
                ],

                const SectionHeader(title: 'Add your own', dense: true),
                TextField(
                  controller: _field,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _addCustom(),
                  decoration: InputDecoration(
                    hintText: 'For…',
                    suffixIcon: IconButton(
                      onPressed: _addCustom,
                      icon: const Icon(Icons.add_rounded),
                      tooltip: 'Add intention',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final category in PrayerCategory.values)
                      ChoiceChip(
                        label: Text(category.label),
                        selected: _category == category,
                        onSelected: (_) =>
                            setState(() => _category = category),
                      ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xl),
                const SectionHeader(title: 'Suggestions', dense: true),
                AsyncView<List<PrayerIntention>>(
                  value: suggestions,
                  onRetry: () => ref.invalidate(suggestedIntentionsProvider),
                  isEmpty: (items) => items.isEmpty,
                  loading: const ShimmerScope(
                    child: Column(
                      children: [
                        SkeletonBox(height: 40, radius: AppRadius.pill),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonBox(height: 40, radius: AppRadius.pill),
                      ],
                    ),
                  ),
                  empty: () => Text(
                    'No suggestions right now — write your own above.',
                    style: theme.textTheme.bodySmall,
                  ),
                  data: (items) => Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final intention in items)
                        FilterChip(
                          label: Text(intention.text),
                          selected: _chosen.any((i) => i.id == intention.id),
                          onSelected: (_) => _toggle(intention),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
            ),
            child: SafeArea(
              top: false,
              child: PrimaryButton(
                label: _chosen.isEmpty
                    ? 'Walk without intentions'
                    : 'Carry ${Fmt.plural(_chosen.length, 'intention')}',
                expand: true,
                onPressed: () => Navigator.of(context).pop(_chosen),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChosenRow extends StatelessWidget {
  const _ChosenRow({required this.intention, required this.onRemove});

  final PrayerIntention intention;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.local_fire_department_rounded,
            size: 18,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(intention.text, style: theme.textTheme.bodyLarge),
                Text(
                  intention.category.label,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Remove "${intention.text}"',
          ),
        ],
      ),
    );
  }
}
