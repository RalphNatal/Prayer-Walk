import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/devotional.dart';
import '../domain/devotional_repository.dart';
import 'supabase_devotional_repository.dart';

/// The real `devotionals` table — the member shelf and the admin content list
/// read the same rows through the same seam.
final devotionalRepositoryProvider = Provider<DevotionalRepository>(
  (ref) => const SupabaseDevotionalRepository(),
);

/// What members browse: published only.
final publishedDevotionalsProvider = FutureProvider<List<Devotional>>(
  (ref) => ref.watch(devotionalRepositoryProvider).published(),
);

/// What the admin content list shows, drafts included. Resolves to the same
/// thing as [publishedDevotionalsProvider] for a non-admin — the table's select
/// policy is what hides drafts, not this provider.
final allDevotionalsProvider = FutureProvider<List<Devotional>>(
  (ref) => ref.watch(devotionalRepositoryProvider).all(),
);

final devotionalProvider = FutureProvider.family<Devotional, String>(
  (ref, id) => ref.watch(devotionalRepositoryProvider).byId(id),
);
