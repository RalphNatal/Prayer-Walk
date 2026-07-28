import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:prayer_walk/src/core/utils/app_exception.dart';
import 'package:prayer_walk/src/core/utils/error_messages.dart';
import 'package:prayer_walk/src/core/widgets/error_report_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// What a failure is allowed to say.
///
/// The rule these guard: the app may only blame the connection when the request
/// genuinely never made it. Everything else names what the server said, or says
/// nothing about the cause at all and offers the details instead.
void main() {
  const fallback = "The walk didn't save.";

  PostgrestException pg(String code, String message) =>
      PostgrestException(message: message, code: code);

  group('Postgres codes', () {
    test('a policy violation is a permission problem, not a network one', () {
      final info = describeFailure(
        pg('42501', 'new row violates row-level security policy'),
        fallback: fallback,
      );

      expect(info.message, "You don't have permission to do that.");
      expect(info.isTransport, isFalse);
    });

    test('a unique violation takes the copy the caller supplied', () {
      final info = describeFailure(
        pg('23505', 'duplicate key value violates unique constraint'),
        fallback: fallback,
        uniqueMessage: 'That handle is taken. Pick another.',
      );

      expect(info.message, 'That handle is taken. Pick another.');
    });

    test('the rest of the table maps to its own line', () {
      expect(
        describeFailure(pg('23503', 'fk violation'), fallback: fallback).message,
        'That item no longer exists.',
      );
      expect(
        describeFailure(pg('23514', 'check constraint'), fallback: fallback).message,
        "That value isn't allowed.",
      );
      expect(
        describeFailure(pg('PGRST116', 'no rows'), fallback: fallback).message,
        "We couldn't find that.",
      );
    });

    test('an unmapped code keeps the neutral line and carries the detail', () {
      final info = describeFailure(
        pg('XX000', 'internal error'),
        fallback: fallback,
      );

      expect(info.message, fallback);
      expect(info.isMapped, isFalse);
      expect(info.message, isNot(contains('connection')));
      expect(info.details, contains('XX000'));
    });
  });

  /// The failure this project keeps hitting: a migration written, committed and
  /// never run. Three times now — `place_name`, `activities`, `devotionals` —
  /// and each time the app said something that named neither the cause nor the
  /// fix. These are the guards that stop a fourth.
  ///
  /// The shared contract for all four codes: mapped, never transport, and the
  /// name of the thing the database is missing survives into the details, where
  /// it is the first line of a one-minute fix rather than a support ticket.
  group('a migration has not been applied', () {
    test('PGRST205 — the table is not in PostgREST\'s schema cache', () {
      final info = describeFailure(
        pg(
          'PGRST205',
          "Could not find the table 'public.devotionals' in the schema cache",
        ),
        fallback: fallback,
      );

      expect(info.code, 'postgres:PGRST205');
      expect(info.message, contains("isn't set up on the server yet"));
      expect(info.isMapped, isTrue);
      expect(info.isSchemaMissing, isTrue);
      expect(info.isTransport, isFalse);
      expect(info.message.toLowerCase(), isNot(contains('connection')));
      // The object, the next step, and — because tests run in debug — the file
      // that would fix it.
      expect(info.details, contains('devotionals'));
      expect(info.details, contains("A database migration hasn't been applied"));
      expect(
        info.details,
        contains('supabase/migrations/20260728020000_devotionals.sql'),
      );
    });

    test('PGRST202 — the RPC is not in the schema cache', () {
      final info = describeFailure(
        pg(
          'PGRST202',
          'Could not find the function public.admin_metrics without parameters '
              'in the schema cache',
        ),
        fallback: fallback,
      );

      expect(info.code, 'postgres:PGRST202');
      expect(info.message, contains("isn't set up on the server yet"));
      expect(info.isMapped, isTrue);
      expect(info.isSchemaMissing, isTrue);
      expect(info.isTransport, isFalse);
      expect(info.details, contains('admin_metrics'));
      expect(
        info.details,
        contains('supabase/migrations/20260728050000_admin_functions.sql'),
      );
    });

    test('42P01 — raw Postgres says the table is undefined', () {
      final info = describeFailure(
        pg('42P01', 'relation "public.announcements" does not exist'),
        fallback: fallback,
      );

      expect(info.code, 'postgres:42P01');
      expect(info.message, contains("isn't set up on the server yet"));
      expect(info.isMapped, isTrue);
      expect(info.isSchemaMissing, isTrue);
      expect(info.isTransport, isFalse);
      expect(info.details, contains('announcements'));
      expect(
        info.details,
        contains('supabase/migrations/20260728040000_announcements.sql'),
      );
    });

    test('42703 — the column is undefined, so the app is ahead', () {
      final info = describeFailure(
        pg(
          '42703',
          'column "place_name" of relation "activities" does not exist',
        ),
        fallback: fallback,
      );

      expect(info.code, 'postgres:42703');
      expect(info.message, contains('newer than the server'));
      expect(info.message, contains('place_name'));
      expect(info.isMapped, isTrue);
      expect(info.isSchemaMissing, isTrue);
      expect(info.isTransport, isFalse);
      expect(info.details, contains('place_name'));
      // The exact server text survives for the details dialog.
      expect(info.details, contains('does not exist'));
    });

    test('none of the four blames the connection', () {
      const cases = {
        'PGRST205': "Could not find the table 'public.devotionals' in the schema cache",
        'PGRST202': 'Could not find the function public.feed_for in the schema cache',
        '42P01': 'relation "public.follows" does not exist',
        '42703': 'column "handle" does not exist',
      };
      for (final entry in cases.entries) {
        final info = describeFailure(
          pg(entry.key, entry.value),
          fallback: fallback,
        );
        expect(info.isTransport, isFalse, reason: entry.key);
        expect(
          info.message.toLowerCase(),
          isNot(contains('connection')),
          reason: '${entry.key} is a missing migration, not a missing network',
        );
        expect(info.isSchemaMissing, isTrue, reason: entry.key);
        expect(
          info.details,
          contains("A database migration hasn't been applied"),
          reason: entry.key,
        );
      }
    });

    test('a permission refusal is a different diagnosis entirely', () {
      // 42501 means the object is there and this account may not touch it —
      // RLS working. Sending someone to run a migration they have already run
      // is the wrong answer twice over.
      final info = describeFailure(
        pg('42501', 'new row violates row-level security policy'),
        fallback: fallback,
      );

      expect(info.isSchemaMissing, isFalse);
      expect(info.isMapped, isTrue);
    });
  });

  group('transport', () {
    test('a timeout may say check your connection', () {
      final info = describeFailure(
        TimeoutException('no answer'),
        fallback: fallback,
      );

      expect(info.isTransport, isTrue);
      expect(info.message, contains('Check your connection'));
    });

    test('so may a client exception', () {
      final info = describeFailure(
        ClientException('connection closed'),
        fallback: fallback,
      );

      expect(info.isTransport, isTrue);
    });

    test('but nothing else does', () {
      for (final error in <Object>[
        pg('42703', 'column "x" does not exist'),
        StateError('bad state'),
        const FormatException('bad json'),
      ]) {
        final info = describeFailure(error, fallback: fallback);
        expect(
          info.message.toLowerCase(),
          isNot(contains('connection')),
          reason: '${error.runtimeType} must not be reported as the network',
        );
        expect(info.isTransport, isFalse);
      }
    });
  });

  test('an already-phrased AppException speaks for itself', () {
    final info = describeFailure(AppException.notFound, fallback: fallback);
    expect(info.message, AppException.notFound.message);
  });

  test('every failure carries a greppable diagnostic', () {
    final info = describeFailure(
      pg('42703', 'column "place_name" does not exist'),
      fallback: fallback,
    );

    expect(info.diagnostic, contains('PostgrestException'));
    expect(info.diagnostic, contains('42703'));
    expect(info.diagnostic, contains('place_name'));
  });

  test('a report carries the code and the message to the dialog', () {
    final report = describeFailure(
      pg('42703', 'column "place_name" does not exist'),
      fallback: fallback,
    ).toReport(tag: 'PW-SUMMARY', title: 'That walk did not save');

    expect(report.tag, 'PW-SUMMARY');
    expect(report.code, 'postgres:42703');
    expect(report.title, 'That walk did not save');
    expect(report.toClipboardText(), contains('42703'));
  });

  /// The dialog shipped headed "That didn't load" over a body reading "That
  /// didn't load." — two lines spent saying one thing, and the person no better
  /// off for either. A heading names the kind of failure; the body names the
  /// consequence. They are never the same sentence.
  group('a heading is not a second copy of the body', () {
    test('a caller that passes one string for both gets a real heading', () {
      final report = ErrorReport(
        tag: 'PW-LOAD',
        code: 'postgres:none',
        title: "That didn't load",
        message: "That didn't load.",
      );

      expect(report.title, isNot(equalsIgnoringCase(report.message)));
      expect(report.message, "That didn't load.");
      expect(report.title, ErrorReport.defaultTitle);
    });

    test('trailing punctuation and case do not smuggle a duplicate through', () {
      for (final pair in const [
        ('Load failed', 'load failed.'),
        ("That didn't send", "That didn't send!"),
        ('What went wrong', 'What went wrong.'),
      ]) {
        final report = ErrorReport(
          tag: 'PW-TEST',
          code: 'test',
          title: pair.$1,
          message: pair.$2,
        );
        expect(
          report.title.toLowerCase().replaceAll(RegExp(r'[.!]+$'), ''),
          isNot(report.message.toLowerCase().replaceAll(RegExp(r'[.!]+$'), '')),
          reason: '"${pair.$1}" over "${pair.$2}" reads as one sentence twice',
        );
      }
    });

    test('a real pair is left exactly as the caller wrote it', () {
      final report = ErrorReport(
        tag: 'PW-LOAD',
        code: 'postgres:PGRST205',
        title: 'Not set up on the server',
        message: "Devotionals couldn't be loaded.",
      );

      expect(report.title, 'Not set up on the server');
      expect(report.message, "Devotionals couldn't be loaded.");
    });

    test('every mapped failure produces a distinct pair through toReport', () {
      const codes = ['PGRST205', 'PGRST202', '42P01', '42703', '42501', 'XX000'];
      for (final code in codes) {
        final report = describeFailure(
          pg(code, 'relation "public.devotionals" does not exist'),
          fallback: "That didn't load.",
        ).toReport(tag: 'PW-LOAD', title: 'Load failed');
        expect(report.title, isNot(report.message), reason: code);
      }
    });
  });
}
