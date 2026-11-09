import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/features/backup/backup_repository.dart';
import 'package:topolina/features/reports/report_repository.dart';
import 'package:topolina/features/authentication/auth_repository.dart';
import 'package:topolina/features/staff/staff_repository.dart';

void main() {
  test(
    'backup envelope preserves exact bigint JSON text and verifies checksum',
    () {
      const payload = '{"expenses":[{"amount_paise":9007199254740993}]}';
      final original = <String, dynamic>{
        'format': 'topolina-backup',
        'version': 1,
        'project_id': 'test-project',
        'payload': payload,
        'sha256': sha256.convert(utf8.encode(payload)).toString(),
      };
      final decoded = BackupCodec.decode(BackupCodec.encode(original));
      expect(decoded['payload'], payload);
      expect(
        (jsonDecode(decoded['payload'])['expenses'][0]['amount_paise']),
        9007199254740993,
      );
      expect(
        () => BackupCodec.decode(BackupCodec.encode(original)..[10] = 0),
        throwsFormatException,
      );
      expect(
        () => BackupCodec.validate({...original, 'payload': 'changed'}),
        throwsFormatException,
      );
      expect(
        () => BackupCodec.validate({...original, 'version': 2}),
        throwsFormatException,
      );
      expect(
        () => BackupCodec.decode(Uint8List.fromList(utf8.encode('[]'))),
        throwsFormatException,
      );
    },
  );
  test('CSV escapes freeform formulas, quotes and newlines and retains exact paise', () {
    expect(csvCell('=HYPERLINK("bad")'), '"\'=HYPERLINK(""bad"")"');
    expect(csvCell(' \t@cmd'), '"\' \t@cmd"');
    expect(csvCell('Vegetables\nFresh'), '"Vegetables\nFresh"');
    expect(decimalPaise(9007199254740993), '90071992547409.93');
    expect(decimalPaise(-10050), '-100.50');
    final bytes = reportCsv({
      'from': '2026-11-01',
      'to': '2026-11-09',
      'expected_paise': 10050,
      'daily': [],
      'expenses': [],
      'payments': [],
    }, {});
    expect(utf8.decode(bytes), contains('100.50'));
  });
  test(
    'salary presentation reuses expense and canonical partial payment IDs',
    () {
      final expense = salaryExpense({
        'expense_id': 'expense',
        'expense_date': '2026-11-09',
        'category_id': 'salary',
        'category_name': 'Salary',
        'staff_name': 'Rahul',
        'salary_month': '2026-11-01',
        'amount_paise': 1500000,
        'paid_paise': 1000000,
        'outstanding_paise': 500000,
        'payment_status': 'partially_paid',
        'payments': [
          {
            'id': 'payment',
            'business_date': '2026-11-09',
            'amount_paise': 1000000,
            'payment_mode': 'cash',
          },
        ],
      });
      expect(expense.id, 'expense');
      expect(expense.payments.single.id, 'payment');
      expect(expense.outstandingPaise, 500000);
    },
  );
  test(
    'permission presentation restricts waiters while admins retain cafe access',
    () {
      final waiter = SessionProfile(
        id: 'w',
        name: 'Waiter',
        role: UserRole.waiter,
        active: true,
        serverTime: DateTime.utc(2026),
        permissions: const [],
      );
      expect(waiter.can('expenses.create'), false);
      expect(waiter.can('admin.manage'), false);
      final admin = SessionProfile(
        id: 'a',
        name: 'Admin',
        role: UserRole.admin,
        active: true,
        serverTime: DateTime.utc(2026),
        permissions: const [],
      );
      expect(admin.can('expenses.create'), true);
    },
  );
}
