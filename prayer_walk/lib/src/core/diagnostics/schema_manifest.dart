/// Which migration creates which database object.
///
/// This project applies SQL by hand in the Supabase SQL editor, so the app and
/// the database drift apart the moment a migration is written but not run. That
/// has now happened three times — `place_name`, then `activities`, then
/// `devotionals` — and each time the app reported a generic failure while the
/// fix was a single file sitting in `supabase/migrations/`.
///
/// This map closes that gap. It is the one place that knows an object's name
/// maps to a file, and it is read by two things:
///
/// * `error_messages.dart`, so a `PGRST205` names the migration to run rather
///   than saying "that didn't load";
/// * `schema_preflight.dart`, so a debug build reports *every* missing object
///   at startup instead of one per screen visit.
///
/// It is deliberately a hand-written constant. Generating it would mean parsing
/// SQL at build time to prevent a class of error that a five-line edit prevents
/// just as well — and the failure mode of a stale entry here is a slightly
/// wrong hint, not a broken app.
library;

/// Tables the app reads or writes, and the migration that creates each.
const Map<String, String> kSchemaTables = {
  'profiles': '20260725000000_profiles_retro_captured.sql',
  'activities': '20260726010000_activities.sql',
  'follows': '20260727010000_social_graph.sql',
  'encouragements': '20260727010000_social_graph.sql',
  'comments': '20260727010000_social_graph.sql',
  'scripture_prompts': '20260727020000_scripture_prompts.sql',
  'devotionals': '20260728020000_devotionals.sql',
  'moderation_reports': '20260728030000_moderation_reports.sql',
  'announcements': '20260728040000_announcements.sql',
};

/// RPCs the app calls, and the migration that creates each.
const Map<String, String> kSchemaFunctions = {
  'feed_for': '20260727010000_social_graph.sql',
  'activities_for': '20260727010000_social_graph.sql',
  'activity_detail': '20260727010000_social_graph.sql',
  'member_stats': '20260727010000_social_graph.sql',
  'admin_metrics': '20260728050000_admin_functions.sql',
  'admin_members': '20260728050000_admin_functions.sql',
  'admin_reports': '20260728050000_admin_functions.sql',
  'admin_resolve_report': '20260728050000_admin_functions.sql',
  'audience_size': '20260728050000_admin_functions.sql',
};

/// Every migration, in the order it must be applied.
///
/// Sorted by filename, which is what the timestamp prefix is for. The preflight
/// uses this to order the files it tells you to run; the README lists the same
/// sequence with a line of prose each.
final List<String> kMigrationOrder = <String>{
  ...kSchemaTables.values,
  ...kSchemaFunctions.values,
  // None of these creates a table or a function the app names directly — they
  // add columns, rewrite triggers, or layer policies onto objects that already
  // exist — so they appear in no map above and would otherwise be missing from
  // the order.
  '20260726000000_profiles_member_fields.sql',
  '20260727000000_activity_place_name.sql',
  '20260728010000_admin_role_rules.sql',
  '20260728060000_suspension_enforcement.sql',
}.toList()..sort();

/// The migration that creates [object], or null if the name is not one of ours.
///
/// Accepts the bare name (`devotionals`), the schema-qualified name
/// (`public.devotionals`) and a function name carrying its argument list
/// (`public.feed_for(viewer, limit_count)`), because those are the three shapes
/// Postgres and PostgREST put in their error messages.
String? migrationForObject(String? object) {
  if (object == null) return null;
  var name = object.trim();
  final paren = name.indexOf('(');
  if (paren > 0) name = name.substring(0, paren);
  name = name.split('.').last.replaceAll('"', '').trim();
  if (name.isEmpty) return null;
  return kSchemaTables[name] ?? kSchemaFunctions[name];
}

/// `supabase/migrations/<file>` — the path as it appears in the repo, which is
/// the form worth putting in a log line someone is about to act on.
String migrationPath(String file) => 'supabase/migrations/$file';
