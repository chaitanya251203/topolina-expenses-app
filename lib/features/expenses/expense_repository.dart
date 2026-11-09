import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/accounting/money.dart';
import '../authentication/auth_repository.dart';

int jsonPaise(Object? value) =>
    value is int ? value : int.parse(value.toString());

String amountInput(int paise) =>
    '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

String expenseDateLabel(String date) {
  final parsed = DateTime.parse(date);
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
}

String paymentModeLabel(String mode) => switch (mode) {
  'cash' => 'Cash',
  'online' => 'Bank / online',
  'other' => 'Other',
  _ => mode,
};

String expenseError(Object error) {
  if (error is ExpenseValidationException) return error.message;
  if (error is FormatException) return error.message;
  if (error is PostgrestException && error.code == '42501') {
    return 'Your account cannot perform this action. Ask your cafe administrator.';
  }
  if (error is PostgrestException &&
      ['P0001', 'P0002', '22023'].contains(error.code)) {
    return error.message;
  }
  return 'We couldn’t save this entry. Check your connection and try again. Your form is still here.';
}

class ExpenseValidationException implements Exception {
  const ExpenseValidationException(this.message);
  final String message;
}

class ExpenseChoice {
  const ExpenseChoice({required this.id, required this.name, this.iconKey});
  final String id, name;
  final String? iconKey;
  factory ExpenseChoice.fromJson(Map<String, dynamic> row) => ExpenseChoice(
    id: row['id'] as String,
    name: row['name'] as String,
    iconKey: row['icon_key'] as String?,
  );
}

class ExpenseItem extends ExpenseChoice {
  const ExpenseItem({
    required super.id,
    required super.name,
    required this.categoryId,
    this.defaultUnit,
    this.defaultRatePaise,
  });
  final String categoryId;
  final String? defaultUnit;
  final int? defaultRatePaise;
  factory ExpenseItem.fromJson(Map<String, dynamic> row) => ExpenseItem(
    id: row['id'] as String,
    name: row['name'] as String,
    categoryId: row['category_id'] as String,
    defaultUnit: row['default_unit'] as String?,
    defaultRatePaise: row['default_rate_paise'] == null
        ? null
        : jsonPaise(row['default_rate_paise']),
  );
}

class ExpenseEntryContext {
  const ExpenseEntryContext({
    required this.serverTime,
    required this.businessDates,
    required this.categories,
    required this.items,
    required this.vendors,
  });
  final DateTime serverTime;
  final List<String> businessDates;
  final List<ExpenseChoice> categories, vendors;
  final List<ExpenseItem> items;
  factory ExpenseEntryContext.fromJson(
    Map<String, dynamic> row,
  ) => ExpenseEntryContext(
    serverTime: DateTime.parse(row['server_time'] as String),
    businessDates: (row['business_dates'] as List)
        .map((d) => d.toString().substring(0, 10))
        .toList(),
    categories: (row['categories'] as List)
        .map((r) => ExpenseChoice.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
    items: (row['items'] as List)
        .map((r) => ExpenseItem.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
    vendors: (row['vendors'] as List)
        .map((r) => ExpenseChoice.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList(),
  );
}

class ExpensePayment {
  const ExpensePayment({
    required this.id,
    required this.date,
    required this.amountPaise,
    required this.mode,
    this.notes,
  });
  final String id, date, mode;
  final int amountPaise;
  final String? notes;
  factory ExpensePayment.fromJson(Map<String, dynamic> row) => ExpensePayment(
    id: row['id'] as String,
    date: row['business_date'].toString().substring(0, 10),
    amountPaise: jsonPaise(row['amount_paise']),
    mode: row['payment_mode'] as String,
    notes: row['notes'] as String?,
  );
}

class ExpenseRecord {
  const ExpenseRecord({
    required this.id,
    required this.date,
    required this.categoryId,
    required this.categoryName,
    required this.description,
    required this.amountPaise,
    required this.paidPaise,
    required this.outstandingPaise,
    required this.status,
    required this.createdBy,
    required this.createdByName,
    required this.payments,
    this.vendorId,
    this.vendorName,
    this.itemName,
    this.quantity,
    this.unit,
    this.ratePaise,
    this.notes,
    this.categoryIconKey,
  });
  final String id,
      date,
      categoryId,
      categoryName,
      description,
      status,
      createdBy,
      createdByName;
  final int amountPaise, paidPaise, outstandingPaise;
  final String? vendorId, vendorName, itemName, quantity, unit, notes;
  final int? ratePaise;
  final String? categoryIconKey;
  final List<ExpensePayment> payments;
  factory ExpenseRecord.fromJson(Map<String, dynamic> row) => ExpenseRecord(
    id: row['id'] as String,
    date: row['business_date'].toString().substring(0, 10),
    categoryId: row['category_id'] as String,
    categoryName: row['category_name'] as String,
    categoryIconKey: row['category_icon_key'] as String?,
    description: row['description'] as String,
    amountPaise: jsonPaise(row['amount_paise']),
    paidPaise: jsonPaise(row['paid_paise']),
    outstandingPaise: jsonPaise(row['outstanding_paise']),
    status: row['payment_status'] as String,
    createdBy: row['created_by'] as String,
    createdByName: row['created_by_name'] as String? ?? 'Staff member',
    vendorId: row['vendor_id'] as String?,
    vendorName: row['vendor_name'] as String?,
    itemName: row['item_name'] as String?,
    quantity: row['quantity']?.toString(),
    unit: row['unit'] as String?,
    ratePaise: row['rate_paise'] == null ? null : jsonPaise(row['rate_paise']),
    notes: row['notes'] as String?,
    payments: (row['payments'] as List? ?? [])
        .map(
          (r) => ExpensePayment.fromJson(Map<String, dynamic>.from(r as Map)),
        )
        .toList(),
  );
}

class ExpenseDraft {
  const ExpenseDraft({
    required this.id,
    required this.date,
    required this.categoryId,
    required this.description,
    required this.amountPaise,
    required this.paidPaise,
    this.paymentMode,
    this.quantity,
    this.unit,
    this.ratePaise,
    this.itemId,
    this.vendorId,
    this.notes,
  });
  final String id, date, categoryId, description;
  final int amountPaise, paidPaise;
  final String? paymentMode, quantity, unit, itemId, vendorId, notes;
  final int? ratePaise;

  void validate() {
    if (categoryId.trim().isEmpty) {
      throw const ExpenseValidationException('Choose an expense category.');
    }
    if (description.trim().isEmpty || description.trim().length > 500) {
      throw const ExpenseValidationException(
        'Enter a description of up to 500 characters.',
      );
    }
    if (amountPaise <= 0) {
      throw const ExpenseValidationException(
        'Enter an amount greater than zero.',
      );
    }
    if (paidPaise < 0 || paidPaise > amountPaise) {
      throw const ExpenseValidationException(
        'The paid amount cannot exceed the expense amount.',
      );
    }
    if (paidPaise > 0 && !['cash', 'online', 'other'].contains(paymentMode)) {
      throw const ExpenseValidationException('Choose how the amount was paid.');
    }
    if ((quantity == null) != (ratePaise == null)) {
      throw const ExpenseValidationException('Enter both quantity and rate.');
    }
    if (quantity != null) {
      final match = RegExp(r'^([0-9]+)(?:\.([0-9]{1,6}))?$')
          .firstMatch(quantity!.trim());
      if (match == null || BigInt.parse(match[1]!) > BigInt.from(9999999999)) {
        throw const ExpenseValidationException(
          'Enter a valid quantity with up to six decimal places.',
        );
      }
      if (Money.calculate(quantity: quantity!, rate: Money(ratePaise!)).paise !=
          amountPaise) {
        throw const ExpenseValidationException(
          'The total must match quantity × rate.',
        );
      }
    }
  }

  Map<String, dynamic> toParams() => {
    'p_id': id,
    'p_date': date,
    'p_category_id': categoryId,
    'p_description': description.trim(),
    'p_amount_paise': amountPaise,
    'p_quantity': quantity?.trim(),
    'p_unit': unit,
    'p_rate_paise': ratePaise,
    'p_item_id': itemId,
    'p_vendor_id': vendorId,
    'p_paid_paise': paidPaise,
    'p_payment_mode': paidPaise == 0 ? null : paymentMode,
    'p_notes': notes,
  };
}

class CreditPaymentDraft {
  const CreditPaymentDraft({
    required this.id,
    required this.expenseId,
    required this.date,
    required this.amountPaise,
    required this.mode,
    this.notes,
  });
  final String id, expenseId, date, mode;
  final int amountPaise;
  final String? notes;
  Map<String, dynamic> toParams() => {
    'p_id': id,
    'p_expense_id': expenseId,
    'p_date': date,
    'p_amount_paise': amountPaise,
    'p_payment_mode': mode,
    'p_notes': notes,
  };
}

/// Reuses a request ID until the submitted values change. A timeout retry must
/// have the same ID, while a changed draft must never silently replay old data.
class ExpenseRequestIdentity {
  String? _fingerprint, _id;
  String forValues(Map<String, dynamic> values) {
    final fingerprint = jsonEncode(values);
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _id = const Uuid().v4();
    }
    return _id!;
  }
}

abstract interface class ExpenseRepository {
  Future<ExpenseEntryContext> entryContext();
  Future<List<ExpenseRecord>> list({
    String? from,
    String? to,
    bool outstandingOnly = false,
  });
  Future<void> create(ExpenseDraft draft);
  Future<void> pay(CreditPaymentDraft draft);
}

class SupabaseExpenseRepository implements ExpenseRepository {
  SupabaseExpenseRepository(this.client);
  final SupabaseClient client;
  @override
  Future<ExpenseEntryContext> entryContext() async =>
      ExpenseEntryContext.fromJson(
        Map<String, dynamic>.from(await client.rpc('entry_context') as Map),
      );
  @override
  Future<List<ExpenseRecord>> list({
    String? from,
    String? to,
    bool outstandingOnly = false,
  }) async {
    final data = await client.rpc(
      'list_expenses',
      params: {
        'p_from': from,
        'p_to': to,
        'p_outstanding_only': outstandingOnly,
      },
    );
    return (data as List)
        .map((r) => ExpenseRecord.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  @override
  Future<void> create(ExpenseDraft draft) async {
    draft.validate();
    await client.rpc('record_expense', params: draft.toParams());
  }

  @override
  Future<void> pay(CreditPaymentDraft draft) async {
    if (draft.amountPaise <= 0 ||
        !['cash', 'online', 'other'].contains(draft.mode)) {
      throw const ExpenseValidationException(
        'Enter a positive payment and choose its payment mode.',
      );
    }
    await client.rpc('record_payment', params: draft.toParams());
  }
}

class FinancialChanges extends Notifier<int> {
  @override
  int build() => 0;
  void changed() => state++;
}

final financialChangesProvider = NotifierProvider<FinancialChanges, int>(
  FinancialChanges.new,
);
final expenseRepositoryProvider = Provider<ExpenseRepository>(
  (ref) => SupabaseExpenseRepository(Supabase.instance.client),
);
final entryContextProvider = FutureProvider.autoDispose<ExpenseEntryContext>((
  ref,
) async {
  ref.watch(authUserProvider);
  ref.watch(financialChangesProvider);
  return ref.watch(expenseRepositoryProvider).entryContext();
});
final expensesProvider = FutureProvider.autoDispose
    .family<List<ExpenseRecord>, String>((ref, date) async {
      ref.watch(authUserProvider);
      ref.watch(financialChangesProvider);
      return ref.watch(expenseRepositoryProvider).list(from: date, to: date);
    });
final creditLedgerProvider = FutureProvider.autoDispose<List<ExpenseRecord>>((
  ref,
) async {
  ref.watch(authUserProvider);
  ref.watch(financialChangesProvider);
  final profile = await ref.watch(profileProvider.future);
  if (profile?.role != UserRole.admin || profile?.active != true) {
    throw const ExpenseValidationException('Administrator access is required.');
  }
  return ref.watch(expenseRepositoryProvider).list(outstandingOnly: true);
});
