// Explicit screenshot QA using test-only data; never writes to Supabase.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/app/theme.dart';
import 'package:topolina/features/authentication/auth_repository.dart';
import 'package:topolina/features/categories/categories_screen.dart';
import 'package:topolina/features/categories/category_repository.dart';
import 'package:topolina/features/dashboard/dashboard_repository.dart';
import 'package:topolina/features/dashboard/workspace_screen.dart';
import 'package:topolina/features/expenses/expense_repository.dart';
import 'package:topolina/features/expenses/expense_form_screen.dart';

import '../test/auth_flow_test.dart' show FakeAuth;
import '../test/expense_flow_test.dart' show FakeExpenseRepository;

void main() {
  final labels = [
    'Bakery',
    'Vegetables',
    'Grocery',
    'Dairy',
    'Salary',
    'Staff Welfare Expense',
    'Conveyance',
    'Rent',
    'Beverages',
    'Frozen',
    'Software',
  ];
  Future<void> capture(WidgetTester tester, String name, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.runAsync(() async {
      final fonts = Directory(
        '.tooling/flutter/bin/cache/artifacts/material_fonts',
      );
      for (final (family, file) in [
        ('Roboto', 'roboto-regular.ttf'),
        ('MaterialIcons', 'materialicons-regular.otf'),
      ]) {
        final bytes = await File('${fonts.path}/$file').readAsBytes();
        await (FontLoader(
          family,
        )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
      }
    });
    final key = GlobalKey();
    final auth = FakeAuth()..id = 'admin';
    addTearDown(auth.changes.close);
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
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
            expenseRepositoryProvider.overrideWithValue(
              FakeExpenseRepository(),
            ),
            categoriesProvider.overrideWith(
              (ref) async => [
                for (var i = 0; i < labels.length; i++)
                  ExpenseCategory(
                    id: 'category-$i',
                    name: labels[i],
                    active: true,
                  ),
              ],
            ),
          ],
          child: MaterialApp(theme: TopolinaTheme.light, home: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  }

  testWidgets(
    'capture category icons and full labels',
    (tester) => capture(tester, 'categories', const CategoriesScreen()),
  );
  testWidgets(
    'capture functional dashboard',
    (tester) => capture(tester, 'overview', const WorkspaceScreen()),
  );
  testWidgets(
    'capture expense entry',
    (tester) => capture(tester, 'expense-entry', const ExpenseFormScreen()),
  );
}
