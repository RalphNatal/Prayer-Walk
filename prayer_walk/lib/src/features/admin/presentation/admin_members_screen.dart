import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/router/admin_shell.dart';
import '../../../core/router/routes.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/widgets.dart';
import '../../profile/domain/user_profile.dart';
import '../data/mock_admin_repository.dart';
import 'widgets/status_pill.dart';

/// The members table: search, filter, drill in.
class AdminMembersScreen extends ConsumerStatefulWidget {
  const AdminMembersScreen({super.key});

  @override
  ConsumerState<AdminMembersScreen> createState() => _AdminMembersScreenState();
}

class _AdminMembersScreenState extends ConsumerState<AdminMembersScreen> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(memberQueryControllerProvider).search,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(adminMembersProvider);
    final query = ref.watch(memberQueryControllerProvider);
    final controller = ref.read(memberQueryControllerProvider.notifier);

    return AdminPage(
      title: 'Members',
      subtitle: members.value == null
          ? null
          : '${Fmt.plural(members.value!.length, 'member')} matching',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: controller.search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search name, handle or parish',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.search.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              controller.search('');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _Filter(
                        label: 'All roles',
                        selected: query.role == null,
                        onSelected: () => controller.setRole(null),
                      ),
                      for (final role in UserRole.values)
                        _Filter(
                          label: role.label,
                          selected: query.role == role,
                          onSelected: () => controller.setRole(role),
                        ),
                      const SizedBox(width: AppSpacing.md),
                      for (final status in MemberStatus.values)
                        _Filter(
                          label: status.label,
                          selected: query.status == status,
                          onSelected: () => controller.setStatus(
                            query.status == status ? null : status,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncView<List<UserProfile>>(
              value: members,
              onRetry: () => ref.invalidate(adminMembersProvider),
              isEmpty: (items) => items.isEmpty,
              loading: const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: RowListLoading(count: 6),
              ),
              empty: () => EmptyState(
                icon: Icons.person_search_outlined,
                title: 'No members match',
                message: 'Clear the search and filters to see everyone.',
                actionLabel: 'Clear filters',
                onAction: () {
                  _search.clear();
                  controller.clear();
                },
              ),
              data: (items) => ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) =>
                    _MemberRow(member: items[index]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Filter extends StatelessWidget {
  const _Filter({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});

  final UserProfile member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      leading: UserAvatar(
        initials: member.initials,
        accentIndex: member.accentIndex,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.displayName,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (member.role == UserRole.admin)
            const StatusPill(label: 'Admin', tone: PillTone.info),
          if (member.status == MemberStatus.suspended) ...[
            const SizedBox(width: AppSpacing.xs),
            const StatusPill(label: 'Suspended', tone: PillTone.danger),
          ],
        ],
      ),
      subtitle: Text(
        '${member.handle}  ·  joined ${Fmt.dayMonthYear(member.joinedAt)}',
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.goNamed(
        Routes.adminMemberDetail,
        pathParameters: {'memberId': member.id},
      ),
    );
  }
}
