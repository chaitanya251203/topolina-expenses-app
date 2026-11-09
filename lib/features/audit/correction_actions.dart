import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/accounting/money.dart';
import '../../core/widgets/entry_dialog.dart';
import '../authentication/auth_repository.dart';
import '../expenses/expense_repository.dart';

class CorrectionActions extends ConsumerWidget {
  const CorrectionActions({super.key, required this.expense, this.payment});
  final ExpenseRecord expense;
  final ExpensePayment? payment;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(profileProvider).asData?.value?.role != UserRole.admin) {
      return const SizedBox.shrink();
    }
    Future<void> run(bool edit) async {
      try {
        final entry = edit
            ? await ref.read(expenseRepositoryProvider).entryContext()
            : null;
        if (!context.mounted) return;
        final identity = ExpenseRequestIdentity();
        final ok = await showEntryForm(
          context,
          title: edit
              ? 'Correct expense'
              : payment == null
              ? 'Void expense'
              : 'Void payment',
          action: edit ? 'Save correction' : 'Confirm void',
          explanation: edit
              ? 'The original entry and your reason remain in audit history. Changing the amount switches to a manual amount. To change the business date, void this entry and record it on the correct open date.'
              : 'This removes the entry from accounting totals and preserves it in audit history. The affected business date must be open. An expense can be voided after its active payments are voided.',
          fields: [
            if (edit) ...[
              EntryField(
                'description',
                'Description',
                value: expense.description,
              ),
              EntryField(
                'amount',
                'Expense amount (₹)',
                value: amountInput(expense.amountPaise),
                kind: EntryKind.money,
              ),
              EntryField(
                'category',
                'Category',
                value: expense.categoryId,
                choices: {
                  expense.categoryId: expense.categoryName,
                  for (final c in entry!.categories) c.id: c.name,
                },
              ),
              EntryField(
                'vendor',
                'Vendor',
                value: expense.vendorId ?? '',
                required: false,
                choices: {
                  '': 'No vendor',
                  if (expense.vendorId != null)
                    expense.vendorId!: expense.vendorName ?? 'Previous vendor',
                  for (final v in entry.vendors) v.id: v.name,
                },
              ),
              EntryField(
                'notes',
                'Notes',
                value: expense.notes ?? '',
                required: false,
              ),
            ],
            const EntryField('reason', 'Reason'),
          ],
          save: (v) async {
            final params = <String, dynamic>{
              'p_reason': v['reason'],
              if (edit) ...{
                'p_expense_id': expense.id,
                'p_description': v['description'],
                'p_amount_paise': Money.parse(v['amount']!).paise,
                'p_category_id': v['category'],
                'p_vendor_id': v['vendor']!.isEmpty ? null : v['vendor'],
                'p_notes': v['notes'],
              } else if (payment != null)
                'p_payment_id': payment!.id
              else
                'p_expense_id': expense.id,
            };
            await Supabase.instance.client.rpc(
              edit
                  ? 'correct_expense'
                  : payment != null
                  ? 'void_payment'
                  : 'void_expense',
              params: {...params, 'p_id': identity.forValues(params)},
            );
          },
        );
        if (ok == true) {
          ref.read(financialChangesProvider.notifier).changed();
          if (context.mounted) Navigator.pop(context);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(expenseError(e))));
        }
      }
    }

    return Wrap(
      spacing: 10,
      children: [
        if (payment == null)
          TextButton.icon(
            onPressed: () => run(true),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Correct expense'),
          ),
        TextButton.icon(
          onPressed: () => run(false),
          icon: const Icon(Icons.block_outlined),
          label: Text(payment == null ? 'Void expense' : 'Void payment'),
        ),
      ],
    );
  }
}
