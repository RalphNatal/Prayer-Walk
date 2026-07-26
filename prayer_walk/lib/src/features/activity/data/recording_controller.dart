import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_providers.dart';
import '../domain/activity.dart';
import 'mock_activity_repository.dart';

/// State carried across the record -> live -> summary flow.
class RecordingState {
  const RecordingState({
    this.type = ActivityType.walk,
    this.intentions = const [],
    this.draft,
    this.isPaused = false,
    this.devotionalTitle,
  });

  final ActivityType type;

  /// Intentions chosen before starting, carried onto the saved activity.
  final List<PrayerIntention> intentions;

  /// Set when the walk was started from a devotional. Shown through the flow
  /// as context; it is not stored on the saved activity — devotional-to-
  /// activity linkage is not modelled yet.
  final String? devotionalTitle;

  /// Set once the (mock) recording begins; the summary edits this in place.
  final ActivityDraft? draft;

  /// The live screen's pause state. Nothing is actually recording — this only
  /// drives which controls are showing.
  final bool isPaused;

  bool get hasDraft => draft != null;

  RecordingState copyWith({
    ActivityType? type,
    List<PrayerIntention>? intentions,
    ActivityDraft? draft,
    bool? isPaused,
    String? devotionalTitle,
    bool clearDraft = false,
    bool clearDevotional = false,
  }) {
    return RecordingState(
      type: type ?? this.type,
      intentions: intentions ?? this.intentions,
      draft: clearDraft ? null : (draft ?? this.draft),
      isPaused: isPaused ?? this.isPaused,
      devotionalTitle: clearDevotional
          ? null
          : (devotionalTitle ?? this.devotionalTitle),
    );
  }
}

class RecordingController extends Notifier<RecordingState> {
  @override
  RecordingState build() => const RecordingState();

  void selectType(ActivityType type) {
    state = state.copyWith(type: type);
  }

  /// Called from the devotional reader's "Start a walk with this".
  void carryDevotional(String title) =>
      state = state.copyWith(devotionalTitle: title);

  void dropDevotional() => state = state.copyWith(clearDevotional: true);

  void toggleIntention(PrayerIntention intention) {
    final existing = state.intentions.any((i) => i.id == intention.id);
    state = state.copyWith(
      intentions: existing
          ? state.intentions.where((i) => i.id != intention.id).toList()
          : [...state.intentions, intention],
    );
  }

  void addIntention(String text, PrayerCategory category) {
    if (text.trim().isEmpty) return;
    state = state.copyWith(
      intentions: [
        ...state.intentions,
        PrayerIntention(
          id: 'i_local_${DateTime.now().microsecondsSinceEpoch}',
          text: text.trim(),
          category: category,
          createdAt: DateTime.now(),
        ),
      ],
    );
  }

  void removeIntention(String id) {
    state = state.copyWith(
      intentions: state.intentions.where((i) => i.id != id).toList(),
    );
  }

  /// MOCK — hands back a pre-traced walk instead of opening a location stream.
  Future<void> start() async {
    final draft = await ref
        .read(activityRepositoryProvider)
        .beginMockRecording(type: state.type, intentions: state.intentions);
    state = state.copyWith(draft: draft, isPaused: false);
  }

  void togglePause() => state = state.copyWith(isPaused: !state.isPaused);

  void editDraft({String? title, String? note}) {
    final draft = state.draft;
    if (draft == null) return;
    state = state.copyWith(draft: draft.copyWith(title: title, note: note));
  }

  void setDraftIntentions(List<PrayerIntention> intentions) {
    final draft = state.draft;
    state = state.copyWith(
      intentions: intentions,
      draft: draft?.copyWith(intentions: intentions),
    );
  }

  /// Commits the draft and clears the flow. Returns the stored activity id.
  Future<String> save() async {
    final draft = state.draft;
    final userId = ref.read(currentUserIdProvider);
    if (draft == null || userId == null) {
      throw StateError('save() called with nothing recorded');
    }
    final saved = await ref
        .read(activityRepositoryProvider)
        .saveDraft(userId, draft);
    reset();
    return saved.id;
  }

  void reset() => state = const RecordingState();
}

final recordingControllerProvider =
    NotifierProvider<RecordingController, RecordingState>(
      RecordingController.new,
    );
