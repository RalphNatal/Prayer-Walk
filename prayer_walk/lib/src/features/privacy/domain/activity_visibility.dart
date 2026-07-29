/// Who a walk is for.
///
/// A GPS trace is not a photograph of a place; it is a record of a person's
/// movement, usually beginning and ending where they sleep. Until this existed
/// the `activities` table had one answer for everybody — `using (true)` — and
/// so every route on the server was readable by every account on it.
///
/// Three values, and the order below is the order of exposure. The wire name is
/// exactly what sits in `activities.visibility`, checked by a constraint in
/// `20260728080000_visibility_zones_blocks.sql`; nothing here decides anything,
/// the database does. This enum exists so that the app talks about the setting
/// in words rather than in string literals scattered across four screens.
library;

enum ActivityVisibility {
  /// Yours alone. Still on your History, still in your totals, never on
  /// anybody else's screen.
  private(
    'private',
    'Only me',
    'Kept to your own history. Nobody else can open it.',
  ),

  /// The default, for new walks and for every walk that existed before the
  /// setting did. A member widens their audience by choosing to; they are
  /// never widened by a migration, a default or an update.
  followers(
    'followers',
    'Followers',
    'People who follow you can see this walk. Nobody else can.',
  ),

  /// Findable by any signed-in member, and the only kind that appears in
  /// Explore.
  public(
    'public',
    'Everyone',
    'Any member can find this walk, including people you have never met.',
  );

  const ActivityVisibility(this.wireName, this.label, this.description);

  /// The value stored in `activities.visibility`.
  final String wireName;

  /// How the setting is named on a control — "Followers".
  final String label;

  /// What choosing it actually does, in a sentence. Shown next to the option
  /// rather than behind a help link: this is the one setting in the app where
  /// not reading the label has a consequence outdoors.
  final String description;

  /// Whether this reaches beyond the people who already know the walker.
  bool get reachesStrangers => this == ActivityVisibility.public;

  /// Row value → setting.
  ///
  /// An unrecognised value resolves to [private] rather than to the column
  /// default. The check constraint makes that unreachable today, so this only
  /// matters if a later migration adds a fourth value and an older build reads
  /// it — and an old build guessing at a new setting should guess in the
  /// direction that shows a walk to fewer people, not more.
  static ActivityVisibility fromWire(String? value) {
    final key = (value ?? '').trim().toLowerCase();
    for (final option in values) {
      if (option.wireName == key) return option;
    }
    return ActivityVisibility.private;
  }

  /// What a new walk starts as when nothing else has said otherwise — the same
  /// value the two columns default to server-side.
  static const standard = ActivityVisibility.followers;
}
