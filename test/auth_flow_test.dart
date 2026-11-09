import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/app/app.dart';
import 'package:topolina/features/authentication/auth_repository.dart';
import 'package:topolina/features/categories/category_repository.dart';
import 'package:topolina/features/dashboard/dashboard_repository.dart';

class FakeAuth implements AuthRepository {
  final changes = StreamController<String?>.broadcast();
  String? id;
  bool active = true, failLogin = false;
  UserRole role = UserRole.admin;
  @override
  Stream<String?> watchUserId() async* {
    yield id;
    yield* changes.stream;
  }

  @override
  Future<SessionProfile> loadProfile() async => SessionProfile(
    id: id!,
    name: role == UserRole.admin ? 'Cafe Admin' : 'Rahul Waiter',
    role: role,
    active: active,
    serverTime: DateTime.parse('2026-11-09T09:00:00Z'),
  );
  @override
  Future<void> signIn(String email, String password) async {
    if (failLogin) throw Exception('network');
    id = 'admin';
    changes.add(id);
  }

  @override
  Future<void> signOut() async {
    id = null;
    changes.add(null);
  }
}

void main() {
  Future<void> open(WidgetTester tester, FakeAuth auth) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          dashboardProvider.overrideWith(
            (ref) async => const DashboardSnapshot({
              'day': {
                'business_date': '2026-11-09',
                'state': 'not_started',
                'has_sales': false,
                'cash_paise': 0,
                'online_paise': 0,
                'other_paise': 0,
                'paid_paise': 0,
              },
            }),
          ),
          categoriesProvider.overrideWith(
            (ref) async => [
              const ExpenseCategory(id: '1', name: 'Grocery', active: true),
              const ExpenseCategory(id: '2', name: 'Salary', active: true),
            ],
          ),
        ],
        child: const TopolinaApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'login validates inputs and displays recoverable connection errors',
    (tester) async {
      final auth = FakeAuth()..failLogin = true;
      addTearDown(auth.changes.close);
      await open(tester, auth);
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email address.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'admin@example.com',
      );
      await tester.enterText(find.byType(TextFormField).last, 'password');
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to sign in. Check your connection and try again.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'login, category search, logout and waiter session do not leak the admin identity',
    (tester) async {
      final auth = FakeAuth()..id = 'admin';
      addTearDown(auth.changes.close);
      await open(tester, auth);
      expect(find.text('Welcome, Cafe.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Expense categories'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Expense categories'));
      await tester.pumpAndSettle();
      expect(find.text('Salary'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'gro');
      await tester.pumpAndSettle();
      expect(find.text('Grocery'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);
      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Welcome, Cafe.'), findsNothing);
      auth.role = UserRole.waiter;
      auth.id = 'waiter';
      auth.changes.add('waiter');
      await tester.pumpAndSettle();
      expect(find.text('Welcome, Rahul.'), findsOneWidget);
      expect(find.text('You’re signed in as an administrator.'), findsNothing);
    },
  );
  testWidgets('inactive account cannot open the workspace', (tester) async {
    final auth = FakeAuth()
      ..id = 'waiter'
      ..active = false;
    addTearDown(auth.changes.close);
    await open(tester, auth);
    expect(find.text('Let’s check your access'), findsOneWidget);
    expect(find.text('Expense categories'), findsNothing);
  });
  testWidgets('small screen and large text keep login usable', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final auth = FakeAuth();
    addTearDown(auth.changes.close);
    await open(tester, auth);
    await tester.ensureVisible(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
