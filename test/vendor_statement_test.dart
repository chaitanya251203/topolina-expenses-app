import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/features/credit/vendor_statement.dart';
import 'package:topolina/features/expenses/expense_repository.dart';

Map<String, dynamic> statementFixture({int count = 2}) => {
  'cafe_name': 'Topolina',
  'reference': 'TOP-20261109-150000-ABC12345',
  'business_date': '2026-11-09',
  'server_time': '2026-11-09T09:30:00Z',
  'vendor': {
    'id': 'vendor',
    'name': 'ABC Fresh Produce & Grocery Suppliers',
    'contact': '+91 98765 43210',
    'address': '12 Market Road, Kalimpong, West Bengal',
  },
  'amount_paise': count * 200050,
  'paid_paise': count * 100000,
  'outstanding_paise': count * 100050,
  'expenses': [
    for (var i = 0; i < count; i++)
      {
        'id': '${i.toString().padLeft(8, '0')}-aaaa-4aaa-aaaa-aaaaaaaaaaaa',
        'business_date': '2026-11-08',
        'description': i % 2 == 0
            ? 'Fresh vegetables - tomatoes, potatoes and seasonal greens'
            : 'Grocery purchase - rice, flour and cooking essentials',
        'amount_paise': 200050,
        'paid_paise': 100000,
        'outstanding_paise': 100050,
        'payments': [
          {
            'id': 'payment-$i-a',
            'business_date': '2026-11-08',
            'amount_paise': 60000,
            'payment_mode': 'cash',
          },
          {
            'id': 'payment-$i-b',
            'business_date': '2026-11-09',
            'amount_paise': 40000,
            'payment_mode': 'online',
          },
        ],
      },
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('vendor statement validates every payment, purchase and total in integer paise', () {
    final data = statementFixture();
    final statement = VendorStatement.fromJson(data);
    expect(statement.outstanding, 200100);
    expect(statement.expenses.length, 2);
    expect(statement.filename, endsWith('.pdf'));
    expect(
      () => VendorStatement.fromJson({...data, 'outstanding_paise': 1}),
      throwsA(isA<ExpenseValidationException>()),
    );
    final broken = statementFixture();
    (broken['expenses'] as List).first['paid_paise'] = 99999;
    expect(
      () => VendorStatement.fromJson(broken),
      throwsA(isA<ExpenseValidationException>()),
    );
  });
  test('vendor statement builds an embedded-font PDF and multi-page payment history', () async {
    for (final count in [2, 60]) {
      final pdf = await buildVendorStatement(
        VendorStatement.fromJson(statementFixture(count: count)),
      );
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(pdf.length, greaterThan(10000));
      final file = File(
        'build/previews/vendor-statement${count == 2 ? '' : '-multipage'}.pdf',
      );
      await file.parent.create(recursive: true);
      await file.writeAsBytes(pdf);
    }
  });
}
