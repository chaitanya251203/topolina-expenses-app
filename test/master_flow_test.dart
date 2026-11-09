import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/app/theme.dart';
import 'package:topolina/features/authentication/auth_repository.dart';
import 'package:topolina/features/masters/master_repository.dart';
import 'package:topolina/features/masters/masters_screen.dart';

class FakeMasters implements MasterRepository {
  Map<String, dynamic>? saved;
  @override
  Future<MasterData> load() async => MasterData({
    MasterKind.categories: [
      const MasterRecord({'id': 'grocery', 'name': 'Grocery', 'active': true}),
    ],
  });
  @override
  Future<void> save(
    MasterKind kind,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    saved = values;
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    FakeMasters repo, {
    UserRole role = UserRole.admin,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileProvider.overrideWith(
            (ref) async => SessionProfile(
              id: 'user',
              name: 'Cafe Admin',
              role: role,
              active: true,
              serverTime: DateTime.utc(2026, 11, 9),
            ),
          ),
          masterRepositoryProvider.overrideWithValue(repo),
          masterDataProvider.overrideWith((ref) => repo.load()),
        ],
        child: MaterialApp(
          theme: TopolinaTheme.light,
          home: const MastersScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('admin creates a category and validates empty names', (
    tester,
  ) async {
    final repo = FakeMasters();
    await open(tester, repo);
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(repo.saved, isNull);
    await tester.enterText(find.byType(TextFormField), 'Bakery');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repo.saved, {
      'name': 'Bakery',
      'active': true,
      'icon_key': 'bakery',
    });
    expect(find.text('Saved successfully'), findsOneWidget);
  });
  testWidgets(
    'deactivation requires confirmation and preserves the same record',
    (tester) async {
      final repo = FakeMasters();
      await open(tester, repo);
      await tester.tap(find.text('Grocery'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Deactivate this record?'), findsOneWidget);
      expect(repo.saved, isNull);
      await tester.tap(find.text('Deactivate'));
      await tester.pumpAndSettle();
      expect(repo.saved?['active'], false);
      expect(repo.saved?['name'], 'Grocery');
    },
  );
  testWidgets('waiter cannot open master management', (tester) async {
    await open(tester, FakeMasters(), role: UserRole.waiter);
    expect(find.text('Administrator access required'), findsOneWidget);
    expect(find.text('Add category'), findsNothing);
  });
}
