import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../domain/bible_translation.dart';
import '../domain/scripture_library.dart';
import '../domain/scripture_prompt.dart';
import '../domain/scripture_repository.dart';
import '../domain/scripture_submission.dart';
import 'scripture_prompt_store.dart';
import 'supabase_scripture_repository.dart';

export 'scripture_announcer.dart'
    show ScriptureAnnouncer, scriptureAnnouncerProvider;
export 'scripture_settings_controller.dart' show scriptureSettingsProvider;

/// The edition this build delivers, and the default an admin form starts from.
///
/// One provider rather than a config read scattered through the app, so the
/// whole thing — delivery, the admin form's default, the credits section —
/// switches together, and so a test can run the app as an NLT build without a
/// rebuild. The value itself comes from `--dart-define`; see
/// [AppConfig.scriptureTranslation].
final appTranslationProvider = Provider<BibleTranslation>(
  (ref) => BibleTranslation.of(AppConfig.scriptureTranslation),
);

final scriptureRepositoryProvider = Provider<ScriptureRepository>(
  (ref) => SupabaseScriptureRepository(
    const ScripturePromptStore(),
    ref.watch(appTranslationProvider).id,
  ),
);

/// The whole published library, fetched once per app run, with its provenance.
///
/// Watched by the record screen so the set is in memory before anyone presses
/// start — a walk must never wait on a network call, and this is where that is
/// arranged. Not auto-disposed on purpose: it is the walk's copy, and it has to
/// outlive the screen that warmed it.
///
/// It resolves rather than failing, because [ScriptureRepository] falls back
/// through the cache and the bundled asset. An empty result means the library
/// is genuinely empty, not that the network is down — and [ScriptureLibrary]
/// says which of those it was.
final loadedScriptureLibraryProvider = FutureProvider<ScriptureLibrary>(
  (ref) => ref.watch(scriptureRepositoryProvider).publishedLibrary(),
);

/// The verses alone — what everything except the diagnostic readout wants.
final scriptureLibraryProvider = FutureProvider<List<ScripturePrompt>>(
  (ref) async => (await ref.watch(loadedScriptureLibraryProvider.future)).prompts,
);

/// The whole table, drafts included — what the admin curation screen lists.
///
/// Unlike [scriptureLibraryProvider] this one is allowed to fail: a curation
/// screen with no network should say so, not quietly show the bundled asset as
/// though it were the table.
final allScripturePromptsProvider =
    FutureProvider.autoDispose<List<ScripturePrompt>>(
      (ref) => ref.watch(scriptureRepositoryProvider).allPrompts(),
    );

// ------------------------------------------------------------ submissions ---

/// Which slice of the submissions queue is showing. Pending first, because a
/// queue exists to be emptied.
class SubmissionFilter extends Notifier<SubmissionStatus?> {
  @override
  SubmissionStatus? build() => SubmissionStatus.pending;

  void set(SubmissionStatus? status) => state = status;
}

final submissionFilterProvider =
    NotifierProvider<SubmissionFilter, SubmissionStatus?>(
      SubmissionFilter.new,
    );

/// The admin queue. Admin-only by RLS — nothing in Dart gates it, for the
/// reason `admin_providers.dart` gives: a second gate is a second place for the
/// answer to live, and the only one that can be wrong.
final scriptureSubmissionsProvider =
    FutureProvider.autoDispose<List<ScriptureSubmission>>(
      (ref) => ref
          .watch(scriptureRepositoryProvider)
          .submissions(status: ref.watch(submissionFilterProvider)),
    );

/// Drives the badge on the admin Scripture screen.
final pendingSubmissionCountProvider = FutureProvider<int>((ref) async {
  final pending = await ref
      .watch(scriptureRepositoryProvider)
      .submissions(status: SubmissionStatus.pending);
  return pending.length;
});

/// What the signed-in member has sent, and what became of it.
final myScriptureSubmissionsProvider =
    FutureProvider.autoDispose<List<ScriptureSubmission>>(
      (ref) => ref.watch(scriptureRepositoryProvider).mySubmissions(),
    );
