import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/widgets.dart';
import '../../devotionals/data/devotional_providers.dart';
import '../data/scripture_providers.dart';
import '../domain/bible_translation.dart';
import 'scripture_quotation.dart';

/// Every edition whose words this app can currently put on a screen.
///
/// Derived from what is actually there rather than from a constant, because the
/// obligation follows the content: the day an NLT row is published, the Tyndale
/// notice has to appear whether or not anybody remembered to change a setting.
/// Four sources feed it:
///
///  * [BibleTranslation.webbe] — always. It is bundled in the binary, so it is
///    quotable even on a device that has never reached the network.
///  * the configured default, which is what a walk delivers.
///  * the prompt library as loaded (Supabase, the cache, or the bundled set).
///  * the published devotional shelf, which quotes scripture of its own.
///
/// Both async sources are read with `.value`, so the section renders
/// immediately and grows if a fetch resolves behind it. A credits list that
/// waits on the network is a credits list that is sometimes absent.
final translationsInUseProvider = Provider<List<BibleTranslation>>((ref) {
  final seen = <BibleTranslation>{
    BibleTranslation.webbe,
    ref.watch(appTranslationProvider),
  };

  for (final prompt in ref.watch(scriptureLibraryProvider).value ?? const []) {
    if (prompt.translationInfo.isQuotation) seen.add(prompt.translationInfo);
  }
  for (final devotional
      in ref.watch(publishedDevotionalsProvider).value ?? const []) {
    if (devotional.translationInfo.isQuotation) {
      seen.add(devotional.translationInfo);
    }
  }

  // Licensed editions first: the notice that is a condition of use should not
  // be reached by scrolling past the one that is a courtesy.
  final all = seen.toList()
    ..sort((a, b) {
      if (a.requiresAttribution != b.requiresAttribution) {
        return a.requiresAttribution ? -1 : 1;
      }
      return a.shortCode.compareTo(b.shortCode);
    });
  return all;
});

/// The scripture credits, in full, on a screen a member actually opens.
///
/// Not a dialog, not behind a chevron, not on a web page somewhere: Tyndale's
/// terms require the notice to appear in the product, and a notice one tap
/// deeper than Settings is a notice that can quietly stop appearing at all. The
/// wording comes from [BibleTranslation.creditLine] verbatim — nothing here
/// reflows or paraphrases it.
class ScriptureCreditsSection extends ConsumerWidget {
  const ScriptureCreditsSection({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final translations = ref.watch(translationsInUseProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeader)
          const SectionHeader(
            title: 'Scripture credits',
            subtitle: 'Where the words on your walks come from.',
          ),
        for (final translation in translations)
          TranslationCreditLine(translation: translation),
      ],
    );
  }
}

/// The same notices, on the app's licence page.
///
/// Registered at startup beside the font licences, so `showLicensePage` — the
/// surface a store reviewer or a curious member reaches through About — carries
/// the scripture terms alongside every package licence Flutter collects. This
/// one is build-time and lists what the build is configured to quote; the
/// in-app [ScriptureCreditsSection] is content-driven and lists what is
/// actually loaded. Both, on purpose: neither alone covers both cases.
void registerScriptureLicences(BibleTranslation configured) {
  LicenseRegistry.addLicense(() async* {
    for (final translation in <BibleTranslation>{
      BibleTranslation.webbe,
      configured,
    }) {
      if (translation.creditLine.isEmpty) continue;
      yield LicenseEntryWithLineBreaks(
        ['Scripture', translation.displayName],
        translation.creditLine,
      );
    }
  });
}
