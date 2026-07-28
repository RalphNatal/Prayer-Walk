import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException;

import '../supabase/supabase_client.dart';
import '../utils/app_logger.dart';
import 'schema_manifest.dart';

/// Asks the database, once at startup, whether it has what the app expects.
///
/// The problem this exists for: migrations in this project are applied by hand
/// in the Supabase SQL editor, so a database can be one, two or six files
/// behind the code that talks to it. When that happens the app does not fail at
/// startup — it fails on whichever screen touches the missing table first,
/// often days later, with an error that names PostgREST's schema cache and
/// nothing a person can act on. That has now cost three separate diagnoses.
///
/// So: one round of tiny queries, run concurrently, that reports *every*
/// missing object at once and names the file that creates each. Fifteen probes
/// with no rows between them; the whole thing costs about what one screen's
/// first load costs, and it runs off the critical path anyway.
///
/// Three rules it does not break:
///
/// * **It never blocks startup.** [run] is fire-and-forget; nothing awaits it.
/// * **It never crashes.** Every probe is caught, and the whole run is wrapped
///   again. A preflight that breaks the app is worse than the drift it reports.
/// * **It is not in release builds.** See [isEnabled] — `kReleaseMode` vetoes
///   it unconditionally, so no dart-define can turn it on in a shipped build.
///
/// It also does not fix anything. It does not create, alter or migrate: it
/// reads, and it tells you what to run. The maintainer applies SQL by hand and
/// that is the point — the app has no business editing its own schema.
abstract final class SchemaPreflight {
  static const _tag = 'PW-SCHEMA';

  /// Set on internal builds with
  /// `--dart-define=PW_SCHEMA_PREFLIGHT=true`, for a profile build handed to
  /// someone whose database might be behind.
  static const bool _flag = bool.fromEnvironment('PW_SCHEMA_PREFLIGHT');

  /// Debug always; an internal profile build if it asked; release never.
  ///
  /// The `!kReleaseMode` is the part that matters. It makes "shipped with the
  /// preflight on" unreachable rather than merely unlikely, which is what
  /// stands between this and a debug banner over someone's prayer walk.
  static bool get isEnabled => !kReleaseMode && (kDebugMode || _flag);

  /// The last result, for the in-app banner to watch. Null until the first run
  /// finishes, and null forever in release.
  static final ValueNotifier<SchemaPreflightReport?> report =
      ValueNotifier<SchemaPreflightReport?>(null);

  static bool _hasRun = false;

  /// Probes every object in the manifest and logs what is missing.
  ///
  /// Safe to call unconditionally and safe to call twice — the gate and the
  /// once-only latch are both in here, so callers do not have to remember
  /// either.
  static Future<void> run() async {
    if (!isEnabled || _hasRun) return;
    _hasRun = true;

    try {
      final started = DateTime.now();
      // The whole point of the exercise: fifteen probes in flight together, so
      // this costs one round trip's latency rather than fifteen.
      final results = await Future.wait([
        for (final table in kSchemaTables.keys) _probeTable(table),
        for (final function in _probedFunctions.keys) _probeFunction(function),
      ]);
      final elapsed = DateTime.now().difference(started);

      final result = SchemaPreflightReport(
        probes: results,
        elapsed: elapsed,
      );
      report.value = result;
      _log(result);
    } catch (error, stackTrace) {
      // Swallowed, loudly. Anything that escapes the per-probe catches is a bug
      // in this file, and a bug in the diagnostics must not become a bug in the
      // app.
      AppLogger.warn(
        _tag,
        'Preflight failed; skipping. This does not affect the app.',
        error,
        stackTrace,
      );
    }
  }

  /// The RPCs worth probing, and the arguments to probe them with.
  ///
  /// `admin_resolve_report` is deliberately absent: it is the one RPC in the
  /// manifest that writes, and a diagnostic that closes a moderation report to
  /// find out whether it can is not a diagnostic. Its migration is the same
  /// file as `admin_metrics`, so nothing is lost — if that file has not been
  /// run, four other probes here say so.
  ///
  /// The arguments are the cheapest legal call for each: a nil UUID matches
  /// nothing, `limit_count: 1` reads at most one row. What comes back is
  /// irrelevant — only whether PostgREST could resolve the function at all.
  static final Map<String, Map<String, dynamic>> _probedFunctions = {
    'feed_for': {'viewer': _viewer, 'limit_count': 1},
    'activities_for': {'target': _viewer, 'viewer': _viewer, 'limit_count': 1},
    'activity_detail': {'activity_id': _nilUuid, 'viewer': _viewer},
    'member_stats': {'target': _viewer},
    'admin_metrics': <String, dynamic>{},
    'admin_members': {'limit_count': 1},
    'admin_reports': <String, dynamic>{},
    'audience_size': {'audience': 'everyone'},
  };

  /// A UUID that is syntactically valid and refers to nobody.
  static const _nilUuid = '00000000-0000-0000-0000-000000000000';

  /// The signed-in member if there is one, so the probe runs as an ordinary
  /// authenticated user and RLS applies to it exactly as it applies to every
  /// other read. Never a service role: a probe that can see what the app cannot
  /// is measuring the wrong database.
  static String get _viewer => supabase.auth.currentUser?.id ?? _nilUuid;

  /// `select … limit 0` — resolves the table, reads no rows.
  static Future<SchemaProbe> _probeTable(String table) async {
    try {
      await supabase.from(table).select('*').limit(0);
      return SchemaProbe(table, SchemaObjectKind.table, ProbeOutcome.present);
    } on PostgrestException catch (error) {
      return SchemaProbe(
        table,
        SchemaObjectKind.table,
        _classify(error),
        detail: error.message,
      );
    } catch (error) {
      // A transport failure, most likely — the device is offline or the
      // project is asleep. Not evidence of anything about the schema.
      return SchemaProbe(
        table,
        SchemaObjectKind.table,
        ProbeOutcome.inconclusive,
        detail: '$error',
      );
    }
  }

  /// A guarded call. Only "the function does not exist" counts as missing —
  /// an admin RPC refusing a non-admin has answered the question.
  static Future<SchemaProbe> _probeFunction(String name) async {
    try {
      await supabase.rpc(name, params: _probedFunctions[name]);
      return SchemaProbe(name, SchemaObjectKind.function, ProbeOutcome.present);
    } on PostgrestException catch (error) {
      return SchemaProbe(
        name,
        SchemaObjectKind.function,
        _classify(error),
        detail: error.message,
      );
    } catch (error) {
      return SchemaProbe(
        name,
        SchemaObjectKind.function,
        ProbeOutcome.inconclusive,
        detail: '$error',
      );
    }
  }

  /// Missing, forbidden, or something else — three different diagnoses that
  /// must not be collapsed.
  ///
  /// `42501` and a bare `raise` from an admin guard both mean the object is
  /// *there* and this user may not touch it, which is RLS working. Reporting
  /// that as a missing migration would send the maintainer to run a file that
  /// is already applied.
  static ProbeOutcome _classify(PostgrestException error) {
    switch (error.code) {
      case 'PGRST205':
      case 'PGRST202':
      case '42P01':
      case '42883':
        return ProbeOutcome.missing;
      case '42501':
      case 'P0001':
        return ProbeOutcome.forbidden;
      default:
        return ProbeOutcome.inconclusive;
    }
  }

  /// One block, one grep. `PW-SCHEMA` finds it; the arrow finds the file.
  static void _log(SchemaPreflightReport result) {
    final missing = result.missing;
    if (missing.isEmpty) {
      AppLogger.info(
        _tag,
        'Schema OK — ${result.probes.length} objects present '
        'in ${result.elapsed.inMilliseconds}ms.'
        '${result.forbidden.isEmpty ? '' : ' (${result.forbidden.length} '
              'present but not readable by this account, which is RLS doing '
              'its job.)'}',
      );
      return;
    }

    final buffer = StringBuffer()
      ..writeln('')
      ..writeln('══════════ ${missing.length} DATABASE '
          'OBJECT${missing.length == 1 ? '' : 'S'} MISSING ══════════')
      ..writeln('The app expects these and this database does not have them.');
    for (final probe in missing) {
      final migration = migrationForObject(probe.name);
      buffer.writeln(
        '  ${probe.kind.label.padRight(8)} ${probe.name.padRight(20)} '
        '→ ${migration == null ? 'no migration in the manifest' : migrationPath(migration)}',
      );
    }

    final files = result.missingMigrations;
    if (files.isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln('Not yet applied, in order:');
      for (var i = 0; i < files.length; i++) {
        buffer.writeln('  ${i + 1}. ${migrationPath(files[i])}');
      }
      buffer
        ..writeln('')
        ..writeln('  npx supabase db push')
        ..writeln('')
        ..writeln('Add --include-all if it refuses because')
        ..writeln('20260725000000_profiles_retro_captured.sql sorts before the')
        ..writeln('last migration on remote — that one is out of order on')
        ..writeln('purpose. See the README.')
        ..writeln('')
        ..writeln("Then reload PostgREST's cache, or PGRST205 will persist for")
        ..writeln('a few seconds after the SQL lands:')
        ..writeln("  NOTIFY pgrst, 'reload schema';");
    }
    buffer.writeln('══════════════════════════════════════════════');

    AppLogger.error(_tag, buffer.toString());
  }
}

enum SchemaObjectKind {
  table('table'),
  function('rpc');

  const SchemaObjectKind(this.label);

  final String label;
}

/// What one probe learned. Four outcomes, because "I could not tell" is an
/// honest answer and a more useful one than a guess.
enum ProbeOutcome {
  /// The object resolved.
  present,

  /// The server says it does not exist. This is the one worth shouting about.
  missing,

  /// It exists; this account may not use it. RLS, working.
  forbidden,

  /// Offline, timed out, or an error this does not recognise. Says nothing
  /// about the schema either way.
  inconclusive,
}

@immutable
class SchemaProbe {
  const SchemaProbe(this.name, this.kind, this.outcome, {this.detail});

  final String name;
  final SchemaObjectKind kind;
  final ProbeOutcome outcome;

  /// The server's own words, for the log.
  final String? detail;
}

/// Everything one preflight run learned.
@immutable
class SchemaPreflightReport {
  const SchemaPreflightReport({required this.probes, required this.elapsed});

  final List<SchemaProbe> probes;
  final Duration elapsed;

  List<SchemaProbe> get missing =>
      probes.where((p) => p.outcome == ProbeOutcome.missing).toList();

  List<SchemaProbe> get forbidden =>
      probes.where((p) => p.outcome == ProbeOutcome.forbidden).toList();

  bool get hasMissing =>
      probes.any((p) => p.outcome == ProbeOutcome.missing);

  /// The migrations to run, deduplicated and in apply order.
  ///
  /// Ordered by the manifest rather than by the order objects happened to fail
  /// in: `social_graph` must land before `admin_functions` regardless of which
  /// probe came back first.
  List<String> get missingMigrations {
    final files = missing
        .map((p) => migrationForObject(p.name))
        .whereType<String>()
        .toSet();
    return kMigrationOrder.where(files.contains).toList(growable: false);
  }
}
