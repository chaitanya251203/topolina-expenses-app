// Screenshot fixtures run only in Flutter's test harness; no hosted data is written.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:topolina/app/theme.dart';
import 'package:topolina/features/authentication/auth_repository.dart';
import 'package:topolina/features/expenses/expense_repository.dart';
import 'package:topolina/features/staff/staff_screen.dart';
import 'package:topolina/features/reports/reports_screen.dart';
import 'package:topolina/features/backup/backup_screen.dart';
import 'package:topolina/features/user_management/users_screen.dart';

import '../test/expense_flow_test.dart' show FakeExpenseRepository;

class _MemoryStorage extends GotrueAsyncStorage {
  @override
  Future<String?> getItem({required String key}) async => null;
  @override
  Future<void> setItem({required String key, required String value}) async {}
  @override
  Future<void> removeItem({required String key}) async {}
}

void main({bool screenshots = true}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  const staff = [
    {
      'id': 'staff',
      'staff_code': 'S001',
      'full_name': 'Rahul Sindhav',
      'designation': 'Cafe Manager',
      'joining_date': '2026-11-01',
      'default_salary_paise': 1500000,
      'active': true,
    },
  ];
  final report = {
    'from': '2026-11-01',
    'to': '2026-11-09',
    'expected_paise': 8500000,
    'cash_paise': 4000000,
    'online_paise': 3200000,
    'other_paise': 300000,
    'incurred_paise': 1650000,
    'paid_paise': 1000000,
    'outstanding_paise': 650000,
    'salary_paid_paise': 500000,
    'categories': [
      {
        'id': 'grocery',
        'name': 'Grocery',
        'icon_key': 'grocery',
        'incurred_paise': 1650000,
        'paid_paise': 1000000,
        'outstanding_paise': 650000,
      },
    ],
    'vendors': [],
    'expenses': [],
    'payments': [],
    'daily': [
      for (var i = 1; i <= 9; i++)
        {
          'business_date': '2026-11-0$i',
          'expected_paise': 900000,
          'cash_paise': 400000,
          'online_paise': 300000,
          'other_paise': 50000,
          'collections_paise': 750000,
          'paid_paise': 150000,
          'filtered_paid_paise': 150000,
          'incurred_paise': 180000,
          'difference_paise': 0,
          'state': 'closed',
        },
    ],
  };
  setUpAll(() async {
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'public-test',
      authOptions: FlutterAuthClientOptions(
        pkceAsyncStorage: _MemoryStorage(),
        persistSession: false,
        detectSessionInUri: false,
        autoRefreshToken: false,
      ),
      httpClient: MockClient((request) async {
        final endpoint = request.url.path.split('/').last;
        final data = switch (endpoint) {
          'staff' => staff,
          'list_payroll' => [
            {
              'id': 'salary',
              'staff_id': 'staff',
              'staff_name': 'Rahul Sindhav',
              'staff_code': 'S001',
              'designation': 'Cafe Manager',
              'salary_month': '2026-11-01',
              'expense_id': 'salary-expense',
              'expense_date': '2026-11-09',
              'category_id': 'salary',
              'category_name': 'Salary',
              'amount_paise': 1500000,
              'paid_paise': 1000000,
              'outstanding_paise': 500000,
              'payment_status': 'partially_paid',
              'payments': [],
            },
          ],
          'get_report' => report,
          'backup_status' => {
            'project_id': 'project',
            'enabled': true,
            'interval_hours': 24,
            'retention': 14,
            'backups': [
              {
                'id': 'backup',
                'created_at': '2026-11-09T12:30:00Z',
                'reason': 'Scheduled backup',
                'size': 16384,
              },
            ],
          },
          'backup_scheduler_status' => true,
          'list_users' => [
            {
              'id': 'admin',
              'full_name': 'Rahul Sindhav',
              'email': 'admin@example.invalid',
              'role_code': 'admin',
              'active': true,
            },
            {
              'id': 'waiter',
              'full_name': 'Cafe Waiter',
              'email': 'waiter@example.invalid',
              'role_code': 'waiter',
              'active': true,
            },
          ],
          'role_permissions' => [
            {'permission_code': 'expenses.create'},
            {'permission_code': 'expenses.read_own'},
          ],
          'download_backup' => {
            'format': 'topolina-backup',
            'version': 1,
            'project_id': 'project',
            'created_at': '2026-11-09T12:30:00Z',
            'payload': '{}',
            'sha256': sha256.convert(utf8.encode('{}')).toString(),
          },
          _ => null,
        };
        return http.Response(
          jsonEncode(data),
          200,
          request: request,
          headers: {'Content-Type': 'application/json'},
        );
      }),
    );
  });
  tearDownAll(() => Supabase.instance.dispose());
  Future<void> capture(WidgetTester tester, String name, Widget page) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    if (screenshots) {
      await tester.runAsync(() async {
        for (final (family, file) in [
          ('Roboto', 'roboto-regular.ttf'),
          ('MaterialIcons', 'materialicons-regular.otf'),
        ]) {
          final bytes = await File(
            '.tooling/flutter/bin/cache/artifacts/material_fonts/$file',
          ).readAsBytes();
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [
            expenseRepositoryProvider.overrideWithValue(
              FakeExpenseRepository(),
            ),
            authUserProvider.overrideWith((ref) => Stream.value('admin')),
            profileProvider.overrideWith(
              (ref) async => SessionProfile(
                id: 'admin',
                name: 'Rahul Sindhav',
                role: UserRole.admin,
                active: true,
                serverTime: DateTime.utc(2026, 11, 9),
              ),
            ),
          ],
          child: MaterialApp(theme: TopolinaTheme.light, home: page),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Unable to load'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    if (screenshots) {
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/previews/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  }

  testWidgets(
    'salary screen renders paid and pending amounts',
    (t) => capture(t, 'salaries', const StaffScreen()),
  );
  testWidgets(
    'report screen renders actual summaries',
    (t) => capture(t, 'reports', const ReportsScreen()),
  );
  testWidgets(
    'backup screen renders scheduler and last successful backup',
    (t) => capture(t, 'backups', const BackupScreen()),
  );
  testWidgets(
    'user screen renders roles and account controls',
    (t) => capture(t, 'users', const UsersScreen()),
  );
}
