import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../expenses/expense_repository.dart';

typedef JsonRow = Map<String, dynamic>;
List<JsonRow> rows(Object? value) =>
    (value as List).map((e) => JsonRow.from(e as Map)).toList();

class StaffRepository {
  StaffRepository(this.client);
  final SupabaseClient client;
  Future<List<JsonRow>> staff() async =>
      rows(await client.from('staff').select().order('full_name'));
  Future<List<JsonRow>> payroll(String month) async =>
      rows(await client.rpc('list_payroll', params: {'p_month': month}));
  Future<void> save(Map<String, dynamic> params) async {
    await client.rpc('save_staff', params: params);
  }

  Future<void> salary(Map<String, dynamic> params) async {
    await client.rpc('create_salary', params: params);
  }
}

final staffRepositoryProvider = Provider(
  (ref) => StaffRepository(Supabase.instance.client),
);
final staffProvider = FutureProvider.autoDispose((ref) {
  ref.watch(financialChangesProvider);
  return ref.watch(staffRepositoryProvider).staff();
});
final payrollProvider = FutureProvider.autoDispose
    .family<List<JsonRow>, String>((ref, month) {
      ref.watch(financialChangesProvider);
      return ref.watch(staffRepositoryProvider).payroll(month);
    });

ExpenseRecord salaryExpense(JsonRow r) => ExpenseRecord(
  id: r['expense_id'],
  date: r['expense_date'],
  categoryId: r['category_id'],
  categoryName: r['category_name'],
  description: '${r['staff_name']} · ${expenseDateLabel(r['salary_month'])}',
  amountPaise: jsonPaise(r['amount_paise']),
  paidPaise: jsonPaise(r['paid_paise']),
  outstandingPaise: jsonPaise(r['outstanding_paise']),
  status: r['payment_status'],
  createdBy: '',
  createdByName: 'Administrator',
  notes: r['notes'],
  payments: rows(r['payments']).map(ExpensePayment.fromJson).toList(),
);
