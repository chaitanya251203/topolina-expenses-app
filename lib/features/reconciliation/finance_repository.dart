import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/accounting/money.dart';
import '../../core/time/business_day.dart';
import '../authentication/auth_repository.dart';
import '../expenses/expense_repository.dart';

int _paise(Object? value) {
  if (value is int) return value;
  if (value is String) return int.parse(value);
  throw const FormatException(
    'Invalid financial amount returned by the server.',
  );
}

class FinancialEntryContext {
  const FinancialEntryContext({
    required this.serverTime,
    required this.businessDates,
  });
  final DateTime serverTime;
  final List<String> businessDates;
  String get today => businessDates.first;

  factory FinancialEntryContext.fromJson(Map<String, dynamic> json) {
    final dates = (json['business_dates'] as List).cast<String>();
    if (dates.isEmpty) throw const FormatException('No current business date.');
    return FinancialEntryContext(
      serverTime: DateTime.parse(json['server_time'] as String),
      businessDates: List.unmodifiable(dates),
    );
  }

  String startingDate(String? requested) {
    if (requested == null) return today;
    final parsed = DateTime.tryParse(requested);
    if (parsed == null ||
        BusinessDay.label(parsed) != requested ||
        requested.compareTo(today) > 0) {
      return today;
    }
    return requested;
  }
}

class DayPayment {
  const DayPayment({
    required this.id,
    required this.expenseId,
    required this.description,
    required this.categoryName,
    required this.amountPaise,
    required this.mode,
    required this.createdByName,
  });
  final String id, expenseId, description, categoryName, mode, createdByName;
  final int amountPaise;
  factory DayPayment.fromJson(Map<String, dynamic> json) => DayPayment(
    id: json['id'] as String,
    expenseId: json['expense_id'] as String,
    description: json['description'] as String,
    categoryName: json['category_name'] as String,
    amountPaise: _paise(json['amount_paise']),
    mode: json['payment_mode'] as String,
    createdByName: json['created_by_name'] as String,
  );
}

class DaySummary {
  const DaySummary({
    required this.businessDate,
    required this.state,
    required this.hasSales,
    required this.expectedPaise,
    required this.cashPaise,
    required this.onlinePaise,
    required this.otherPaise,
    required this.paidPaise,
    required this.incurredPaise,
    required this.outstandingPaise,
    required this.differencePaise,
    this.notes,
    this.payments = const [],
  });
  final String businessDate, state;
  final bool hasSales;
  final int? expectedPaise, differencePaise;
  final int cashPaise,
      onlinePaise,
      otherPaise,
      paidPaise,
      incurredPaise,
      outstandingPaise;
  final String? notes;
  final List<DayPayment> payments;

  bool get isClosed => state == 'closed';
  bool canEdit(FinancialEntryContext context) =>
      !isClosed &&
      (state == 'reopened' || context.businessDates.contains(businessDate));
  int get collectionsPaise => Reconciliation(
    expected: const Money(0),
    cash: Money(cashPaise),
    online: Money(onlinePaise),
    other: Money(otherPaise),
    paid: const Money(0),
  ).collectionsPaise;
  int get accountedPaise {
    final value = BigInt.from(collectionsPaise) + BigInt.from(paidPaise);
    if (value > BigInt.parse('9223372036854775807')) {
      throw RangeError('Total is too large.');
    }
    return value.toInt();
  }

  String get balanceLabel => differencePaise == null
      ? 'Sales not recorded'
      : differencePaise == 0
      ? 'Balanced'
      : differencePaise! > 0
      ? 'Short'
      : 'Excess';
  String get stateLabel => switch (state) {
    'not_started' => 'Not started',
    'closed' => 'Closed',
    'reopened' => 'Reopened',
    _ => 'In progress',
  };

  factory DaySummary.fromJson(Map<String, dynamic> json) => DaySummary(
    businessDate: json['business_date'] as String,
    state: json['state'] as String,
    hasSales: json['has_sales'] as bool,
    expectedPaise: json['expected_paise'] == null
        ? null
        : _paise(json['expected_paise']),
    cashPaise: _paise(json['cash_paise'] ?? 0),
    onlinePaise: _paise(json['online_paise'] ?? 0),
    otherPaise: _paise(json['other_paise'] ?? 0),
    paidPaise: _paise(json['paid_paise'] ?? 0),
    incurredPaise: _paise(json['incurred_paise'] ?? 0),
    outstandingPaise: _paise(json['outstanding_paise'] ?? 0),
    differencePaise: json['difference_paise'] == null
        ? null
        : _paise(json['difference_paise']),
    notes: json['notes'] as String?,
    payments: List.unmodifiable(
      (json['payments'] as List? ?? []).map(
        (p) => DayPayment.fromJson(Map<String, dynamic>.from(p as Map)),
      ),
    ),
  );
}

class SalesDraft {
  const SalesDraft({
    required this.businessDate,
    required this.expectedPaise,
    required this.cashPaise,
    required this.onlinePaise,
    required this.otherPaise,
    this.notes,
  });
  final String businessDate;
  final int expectedPaise, cashPaise, onlinePaise, otherPaise;
  final String? notes;
}

abstract interface class FinanceRepository {
  Future<FinancialEntryContext> entryContext();
  Future<DaySummary> day(String date);
  Future<void> saveSales(SalesDraft draft);
  Future<void> closeDay(String date, String? reason);
  Future<void> reopenDay(String date, String reason);
}

class SupabaseFinanceRepository implements FinanceRepository {
  SupabaseFinanceRepository(this.client);
  final SupabaseClient client;
  @override
  Future<FinancialEntryContext> entryContext() async =>
      FinancialEntryContext.fromJson(
        Map<String, dynamic>.from(await client.rpc('entry_context') as Map),
      );
  @override
  Future<DaySummary> day(String date) async => DaySummary.fromJson(
    Map<String, dynamic>.from(
      await client.rpc('get_day', params: {'p_date': date}) as Map,
    ),
  );
  @override
  Future<void> saveSales(SalesDraft draft) async {
    await client.rpc(
      'save_sales',
      params: {
        'p_date': draft.businessDate,
        'p_expected_paise': draft.expectedPaise,
        'p_cash_paise': draft.cashPaise,
        'p_online_paise': draft.onlinePaise,
        'p_other_paise': draft.otherPaise,
        'p_notes': draft.notes,
      },
    );
  }

  @override
  Future<void> closeDay(String date, String? reason) async {
    await client.rpc('close_day', params: {'p_date': date, 'p_reason': reason});
  }

  @override
  Future<void> reopenDay(String date, String reason) async {
    await client.rpc(
      'reopen_day',
      params: {'p_date': date, 'p_reason': reason},
    );
  }
}

final financeRepositoryProvider = Provider<FinanceRepository>(
  (ref) => SupabaseFinanceRepository(Supabase.instance.client),
);

void _requireAdmin(SessionProfile? profile) {
  if (profile == null || !profile.active || profile.role != UserRole.admin) {
    throw const FinanceAccessException();
  }
}

class FinanceAccessException implements Exception {
  const FinanceAccessException();
}

final financialEntryContextProvider =
    FutureProvider.autoDispose<FinancialEntryContext>((ref) async {
      _requireAdmin(ref.watch(profileProvider).asData?.value);
      ref.watch(financialChangesProvider);
      return ref.watch(financeRepositoryProvider).entryContext();
    });
final daySummaryProvider = FutureProvider.autoDispose
    .family<DaySummary, String>((ref, date) async {
      _requireAdmin(ref.watch(profileProvider).asData?.value);
      ref.watch(financialChangesProvider);
      return ref.watch(financeRepositoryProvider).day(date);
    });

String financeErrorMessage(Object error) {
  if (error is FinanceAccessException) {
    return 'This section is available to administrators.';
  }
  if (error is PostgrestException &&
      ['P0001', 'P0002', '22023'].contains(error.code)) {
    return error.message;
  }
  if (error is PostgrestException && error.code == '42501') {
    return 'Your account cannot perform this action. Ask an administrator for help.';
  }
  return 'Could not reach your cafe workspace. Check your connection and try again.';
}
