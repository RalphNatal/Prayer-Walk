import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/scripture_prompt.dart';
import '../domain/scripture_repository.dart';
import 'supabase_scripture_repository.dart';

export 'scripture_announcer.dart'
    show ScriptureAnnouncer, scriptureAnnouncerProvider;
export 'scripture_settings_controller.dart' show scriptureSettingsProvider;

final scriptureRepositoryProvider = Provider<ScriptureRepository>(
  (ref) => const SupabaseScriptureRepository(),
);

/// The whole published library, fetched once per app run.
///
/// Watched by the record screen so the set is in memory before anyone presses
/// start — a walk must never wait on a network call, and this is where that is
/// arranged. Not auto-disposed on purpose: it is the walk's copy, and it has to
/// outlive the screen that warmed it.
///
/// It resolves to a list rather than failing, because [ScriptureRepository]
/// falls back through the cache and the bundled asset. An empty result means
/// the library is genuinely empty, not that the network is down.
final scriptureLibraryProvider = FutureProvider<List<ScripturePrompt>>(
  (ref) => ref.watch(scriptureRepositoryProvider).publishedPrompts(),
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
