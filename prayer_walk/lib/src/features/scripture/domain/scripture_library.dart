import 'bible_translation.dart';
import 'scripture_prompt.dart';

/// Where the verses on this device actually came from.
///
/// The question that this whole diagnostic exists to answer. A walker reporting
/// "these are not the verses I configured" has five possible causes and only one
/// of them is visible from the text itself; the other four are all answered by
/// knowing which of these three doors the library came through, and what it held
/// when it arrived.
enum ScriptureLibrarySource {
  /// Read from Supabase on this app run. The newest an admin has published.
  network('network'),

  /// The last successful sync, replayed from local storage. Whatever the table
  /// held the last time this device had signal.
  cache('cache'),

  /// `assets/scripture/prompts.json`, shipped inside the binary. **Always
  /// public-domain WEBBE**, whatever edition the build is configured to
  /// deliver — see `ScripturePromptStore.readBundled`. A walker on an NLT build
  /// reading WEBBE verses is almost always this, and this is the value that
  /// says so.
  bundled('bundled asset'),

  /// Nothing anywhere. A packaging fault rather than a runtime condition.
  none('nothing');

  const ScriptureLibrarySource(this.label);

  /// How the debug readout names it.
  final String label;
}

/// A loaded library, and the provenance a diagnostic needs to explain it.
///
/// [ScriptureRepository.publishedPrompts] answers with the verses alone, which
/// is all a walk needs. This carries the same verses plus the three facts that
/// distinguish "the NLT was never seeded" from "the NLT is seeded and this
/// device could not reach it": where the set came from, which edition was asked
/// for, and whether the edition filter had to give up.
class ScriptureLibrary {
  const ScriptureLibrary({
    required this.prompts,
    required this.source,
    required this.requested,
    required this.available,
    this.fellBack = false,
  });

  const ScriptureLibrary.empty()
    : prompts = const [],
      source = ScriptureLibrarySource.none,
      requested = BibleTranslation.fallback,
      available = const [],
      fellBack = false;

  /// What a walk will draw from: theme- and edition-filtered.
  final List<ScripturePrompt> prompts;

  final ScriptureLibrarySource source;

  /// The edition the build asked for — `AppConfig.scriptureTranslation`.
  final BibleTranslation requested;

  /// Everything the source held, before the edition filter. Kept because the
  /// interesting number is what was *not* selected: "0 NLT" is the answer to
  /// the complaint, and it cannot be read off [prompts].
  final List<ScripturePrompt> available;

  /// Whether [requested] had no quotations at all and the whole library was
  /// delivered instead. True is the "you asked for an edition that is not
  /// there" case, and it is the one worth saying out loud.
  final bool fellBack;

  /// How many prompts of each edition the source held, keyed by the edition's
  /// short code. Prayers, which quote nobody, are counted under an empty key
  /// so they are visible without being mistaken for a translation.
  Map<String, int> get countsByTranslation {
    final counts = <String, int>{};
    for (final prompt in available) {
      final key = prompt.translationInfo.isQuotation
          ? prompt.translationInfo.shortCode
          : '';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  /// What is actually being delivered, once the filter and the fallback have
  /// both had their say. This is the honest answer to "which translation am I
  /// reading", and it is not always [requested].
  Set<BibleTranslation> get deliveredTranslations => {
    for (final prompt in prompts)
      if (prompt.translationInfo.isQuotation) prompt.translationInfo,
  };
}
