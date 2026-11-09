import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../expenses/expense_repository.dart';
import '../staff/staff_repository.dart';

class ReportRepository {
  ReportRepository(this.client);
  final SupabaseClient client;
  Future<JsonRow> load(Map<String, dynamic> params) async =>
      JsonRow.from(await client.rpc('get_report', params: params) as Map);
}

final reportRepositoryProvider = Provider(
  (ref) => ReportRepository(Supabase.instance.client),
);

String csvCell(Object? value) {
  var text = value?.toString() ?? '';
  if (RegExp(r'^\s*[=+@\-\t\r]').hasMatch(text)) text = "'$text";
  return '"${text.replaceAll('"', '""')}"';
}

String decimalPaise(Object? v) {
  final n = jsonPaise(v ?? 0);
  final a = n.abs();
  return '${n < 0 ? '-' : ''}${a ~/ 100}.${(a % 100).toString().padLeft(2, '0')}';
}

Uint8List reportCsv(JsonRow report, Map<String, dynamic> filters) {
  final lines = <List<Object?>>[
    ['Topolina accounting report'],
    ['From', report['from'], 'Through', report['to']],
    ['Filters', jsonEncode(filters)],
    [
      'Sales and daily reconciliation include all categories. Expense sections follow selected filters.',
    ],
    [
      'Outstanding is as of the end date, including older purchases. All money values are INR.',
    ],
    [],
    [
      'Expected sales',
      'Cash collections',
      'Online collections',
      'Other collections',
      'Expenses incurred',
      'Expenses paid',
      'Outstanding',
      'Linked salary paid',
    ],
    [
      for (final k in [
        'expected_paise',
        'cash_paise',
        'online_paise',
        'other_paise',
        'incurred_paise',
        'paid_paise',
        'outstanding_paise',
        'salary_paid_paise',
      ])
        decimalPaise(report[k]),
    ],
    [],
    ['Daily reconciliation (all categories)'],
    [
      'Date',
      'State',
      'Expected',
      'Cash',
      'Online',
      'Other',
      'Paid',
      'Difference',
      'Filtered incurred',
      'Filtered paid',
    ],
    for (final r in rows(report['daily']))
      [
        r['business_date'],
        r['state'],
        r['expected_paise'] == null ? '' : decimalPaise(r['expected_paise']),
        decimalPaise(r['cash_paise']),
        decimalPaise(r['online_paise']),
        decimalPaise(r['other_paise']),
        decimalPaise(r['paid_paise']),
        r['difference_paise'] == null
            ? ''
            : decimalPaise(r['difference_paise']),
        decimalPaise(r['incurred_paise']),
        decimalPaise(r['filtered_paid_paise']),
      ],
    [],
    ['Expense purchases (selected date range and filters)'],
    [
      'ID',
      'Purchase date',
      'Description',
      'Category',
      'Vendor',
      'Staff',
      'Amount',
      'Paid through end date',
      'Outstanding through end date',
      'Status',
      'Notes',
    ],
    for (final r in rows(report['expenses']))
      [
        r['id'],
        r['business_date'],
        r['description'],
        r['category_name'],
        r['vendor_name'],
        r['staff_name'],
        decimalPaise(r['amount_paise']),
        decimalPaise(r['paid']),
        decimalPaise(r['outstanding']),
        r['status'],
        r['notes'],
      ],
    [],
    ['Actual payments (selected payment dates and filters)'],
    [
      'Payment ID',
      'Expense ID',
      'Payment date',
      'Purchase date',
      'Description',
      'Category',
      'Vendor',
      'Staff',
      'Amount',
      'Mode',
      'Notes',
    ],
    for (final r in rows(report['payments']))
      [
        r['id'],
        r['expense_id'],
        r['business_date'],
        r['purchase_date'],
        r['description'],
        r['category_name'],
        r['vendor_name'],
        r['staff_name'],
        decimalPaise(r['amount_paise']),
        r['payment_mode'],
        r['notes'],
      ],
  ];
  return Uint8List.fromList(
    utf8.encode(
      '\uFEFF${lines.map((l) => l.map(csvCell).join(',')).join('\r\n')}',
    ),
  );
}
