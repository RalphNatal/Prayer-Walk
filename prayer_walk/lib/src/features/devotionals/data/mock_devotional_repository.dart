import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/mock_backend/mock_backend.dart';
import '../domain/devotional.dart';
import '../domain/devotional_repository.dart';

class MockDevotionalRepository implements DevotionalRepository {
  MockDevotionalRepository(this._backend);

  final MockBackend _backend;

  @override
  Future<List<Devotional>> published({DevotionalCategory? category}) {
    return _backend.readList(() {
      final rows =
          _backend.devotionals
              .where((d) => d.isPublished)
              .where((d) => category == null || d.category == category)
              .toList()
            ..sort((a, b) {
              final ap = a.publishedAt ?? a.updatedAt;
              final bp = b.publishedAt ?? b.updatedAt;
              return bp.compareTo(ap);
            });
      return rows;
    });
  }

  @override
  Future<List<Devotional>> all() {
    return _backend.readList(
      () => _backend.devotionals.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
    );
  }

  @override
  Future<Devotional> byId(String id) =>
      _backend.read(() => _backend.devotionalById(id));

  @override
  Future<Devotional> save(DevotionalDraft draft, {required String authorName}) {
    return _backend.write(() {
      final now = DateTime.now();
      final id = draft.id;
      if (id == null) {
        final created = Devotional(
          id: _backend.nextId('d'),
          title: draft.title.trim(),
          summary: draft.summary.trim(),
          body: draft.body.trim(),
          category: draft.category,
          authorName: authorName,
          updatedAt: now,
          publishedAt: draft.isPublished ? now : null,
          isPublished: draft.isPublished,
          scriptureRef: draft.scriptureRef.trim(),
          scriptureText: draft.scriptureText.trim(),
          readMinutes: _estimateReadMinutes(draft.body),
        );
        _backend.devotionals.add(created);
        return created;
      }

      final existing = _backend.devotionalById(id);
      final updated = existing.copyWith(
        title: draft.title.trim(),
        summary: draft.summary.trim(),
        body: draft.body.trim(),
        category: draft.category,
        scriptureRef: draft.scriptureRef.trim(),
        scriptureText: draft.scriptureText.trim(),
        isPublished: draft.isPublished,
        updatedAt: now,
        publishedAt: draft.isPublished ? (existing.publishedAt ?? now) : null,
        readMinutes: _estimateReadMinutes(draft.body),
      );
      _backend.replaceDevotional(updated);
      return updated;
    });
  }

  @override
  Future<Devotional> setPublished(String id, {required bool published}) {
    return _backend.write(() {
      final existing = _backend.devotionalById(id);
      final updated = existing.copyWith(
        isPublished: published,
        updatedAt: DateTime.now(),
        publishedAt: published
            ? (existing.publishedAt ?? DateTime.now())
            : null,
      );
      _backend.replaceDevotional(updated);
      return updated;
    });
  }

  @override
  Future<void> delete(String id) =>
      _backend.write(() => _backend.devotionals.removeWhere((d) => d.id == id));

  /// ~200 words a minute, floor of one.
  int _estimateReadMinutes(String body) {
    final words = body.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return (words / 200).ceil().clamp(1, 60);
  }
}

final devotionalRepositoryProvider = Provider<DevotionalRepository>(
  (ref) => MockDevotionalRepository(ref.watch(mockBackendProvider)),
);

/// What members browse.
final publishedDevotionalsProvider = FutureProvider<List<Devotional>>(
  (ref) => ref.watch(devotionalRepositoryProvider).published(),
);

/// What the admin content list shows, drafts included.
final allDevotionalsProvider = FutureProvider<List<Devotional>>(
  (ref) => ref.watch(devotionalRepositoryProvider).all(),
);

final devotionalProvider = FutureProvider.family<Devotional, String>(
  (ref, id) => ref.watch(devotionalRepositoryProvider).byId(id),
);
