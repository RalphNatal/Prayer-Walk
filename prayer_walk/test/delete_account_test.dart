import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prayer_walk/src/core/theme/app_theme.dart';
import 'package:prayer_walk/src/features/auth/data/auth_repository.dart';
import 'package:prayer_walk/src/features/auth/domain/profile.dart';
import 'package:prayer_walk/src/features/profile/presentation/delete_account_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthResponse, AuthState, PostgrestException, Session, User;

/// A stand-in for the real `AuthRepository`, in the same shape as
/// `_FailingRepository implements ActivityRepository` in
/// `save_failure_test.dart`: only what this screen actually calls is real,
/// everything else is an `UnimplementedError` nobody here should ever reach.
class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.deleteError, this.exportError, this.exportResult});

  final Object? deleteError;
  final Object? exportError;
  final Map<String, dynamic>? exportResult;

  int deleteCalls = 0;
  int exportCalls = 0;

  @override
  Future<void> deleteAccount() async {
    deleteCalls++;
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<Map<String, dynamic>> exportData() async {
    exportCalls++;
    if (exportError != null) throw exportError!;
    return exportResult ?? const {};
  }

  @override
  Stream<AuthState> authStateChanges() => throw UnimplementedError();

  @override
  Session? get currentSession => throw UnimplementedError();

  @override
  User? get currentUser => throw UnimplementedError();

  @override
  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    String? fullName,
  }) async => throw UnimplementedError();

  @override
  Future<Profile> fetchProfile(String userId) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async => throw UnimplementedError();

  @override
  Future<AuthResponse> signInWithGoogle() async => throw UnimplementedError();
}

void main() {
  Future<_FakeAuthRepository> pumpScreen(
    WidgetTester tester, {
    Object? deleteError,
    Object? exportError,
    Map<String, dynamic>? exportResult,
  }) async {
    final repository = _FakeAuthRepository(
      deleteError: deleteError,
      exportError: exportError,
      exportResult: exportResult,
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(412, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const DeleteAccountScreen(),
        ),
      ),
    );
    await tester.pump();
    return repository;
  }

  FilledButton deleteButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.widgetWithText(FilledButton, 'Delete my account'),
  );

  testWidgets('the delete button stays disabled until DELETE is typed', (
    tester,
  ) async {
    await pumpScreen(tester);

    expect(deleteButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();

    expect(deleteButton(tester).onPressed, isNotNull);
  });

  testWidgets('a mistyped confirmation still leaves it disabled', (
    tester,
  ) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'delete my account');
    await tester.pump();

    expect(deleteButton(tester).onPressed, isNull);
  });

  testWidgets('a successful deletion calls the repository once', (
    tester,
  ) async {
    final repository = await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete my account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.deleteCalls, 1);
  });

  testWidgets('a scripted failure shows the mapped message and stays on '
      'screen, retryable', (tester) async {
    final repository = await pumpScreen(
      tester,
      deleteError: PostgrestException(
        message: 'new row violates row-level security policy',
        code: '42501',
      ),
    );

    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete my account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text("You don't have permission to do that."), findsOneWidget);
    // Still here, not swept away by a redirect — the delete button is back
    // and could be pressed again.
    expect(find.widgetWithText(FilledButton, 'Delete my account'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(repository.deleteCalls, 2);
  });

  testWidgets('exporting renders the returned data', (tester) async {
    await pumpScreen(
      tester,
      exportResult: {
        'profile': {'id': 'u_walker', 'full_name': 'A Walker'},
        'activities': [],
      },
    );

    await tester.tap(find.text('Export your data first'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('u_walker'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });
}
