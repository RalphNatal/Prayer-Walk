import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:prayer_walk/src/core/utils/app_exception.dart';
import 'package:prayer_walk/src/core/utils/error_messages.dart';
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
    test('42703 names the column the server does not have', () {
      final info = describeFailure(
        pg('42703', 'column "place_name" of relation "activities" does not exist'),
        fallback: fallback,
      );

      expect(info.code, 'postgres:42703');
      expect(info.message, contains('out of date with the server'));
      expect(info.message, contains('place_name'));
      expect(info.isTransport, isFalse);
      expect(info.isMapped, isTrue);
      // The exact server text survives for the details dialog.
      expect(info.details, contains('does not exist'));
    });

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
        describeFailure(pg('42P01', 'relation does not exist'), fallback: fallback).message,
        contains('contact support'),
      );
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
}
