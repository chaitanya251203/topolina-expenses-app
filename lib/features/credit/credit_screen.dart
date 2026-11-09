import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/accounting/money.dart';
import '../../core/time/business_day.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/status_panel.dart';
import '../authentication/auth_repository.dart';
import '../expenses/expense_repository.dart';
import '../expenses/expense_widgets.dart';
import 'vendor_statement.dart';
import 'vendor_statement_screen.dart';

Future<bool?> showLedgerPayment(
  BuildContext context,
  ExpenseRecord record,
  ExpenseEntryContext entry,
) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  isDismissible: false,
  enableDrag: false,
  builder: (_) => _PaymentSheet(record: record, entry: entry),
);

final creditPaidMonthProvider = FutureProvider.autoDispose<int>((ref) async {
  ref.watch(financialChangesProvider);
  final data = await Supabase.instance.client.rpc('get_credit_summary') as Map;
  return jsonPaise(data['paid_this_month_paise']);
});

class CreditScreen extends ConsumerStatefulWidget {
  const CreditScreen({super.key});
  @override
  ConsumerState<CreditScreen> createState() => _CreditScreenState();
}

class _CreditScreenState extends ConsumerState<CreditScreen> {
  bool _openingPayment = false;
  bool _openingStatement = false;
  Future<void> _statement(String vendor) async {
    if (_openingStatement) return;
    setState(() => _openingStatement = true);
    try {
      final data = Map<String, dynamic>.from(
        await Supabase.instance.client.rpc(
          'get_vendor_statement',
          params: {'p_vendor_id': vendor},
        ) as Map,
      );
      final statement = VendorStatement.fromJson(data);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VendorStatementScreen(statement: statement),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(expenseError(e))));
      }
    } finally {
      if (mounted) setState(() => _openingStatement = false);
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(creditLedgerProvider);
    ref.invalidate(entryContextProvider);
    try {
      await ref.read(creditLedgerProvider.future);
    } catch (_) {
      /* Provider displays the retry state. */
    }
  }

  Future<void> _pay(ExpenseRecord record) async {
    if (_openingPayment) return;
    setState(() => _openingPayment = true);
    try {
      ref.invalidate(entryContextProvider);
      final entry = await ref.read(entryContextProvider.future);
      if (!mounted) return;
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        builder: (context) => _PaymentSheet(record: record, entry: entry),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open payment entry. Check your connection and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingPayment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider).asData?.value;
    if (profile?.role != UserRole.admin || profile?.active != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Credit ledger')),
        body: const StatusPanel(
          icon: Icons.lock_outline,
          title: 'Administrator access required',
          message: 'Credit payments are managed by your cafe administrator.',
        ),
      );
    }
    ref.watch(entryContextProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Credit ledger'),
        actions: [
          IconButton(
            tooltip: 'Refresh credit ledger',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ref
          .watch(creditLedgerProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => StatusPanel(
              icon: Icons.wifi_off_outlined,
              title: 'Unable to load credit balances',
              message: 'Check your connection and try again.',
              action: FilledButton(
                onPressed: _refresh,
                child: const Text('Try again'),
              ),
            ),
            data: (records) {
              final groups = <String, List<ExpenseRecord>>{};
              for (final record in records) {
                groups.putIfAbsent(record.vendorId ?? '', () => []).add(record);
              }
              final total = records.fold(
                BigInt.zero,
                (sum, record) => sum + BigInt.from(record.outstandingPaise),
              );
              if (!total.isValidInt) {
                return const StatusPanel(
                  icon: Icons.error_outline,
                  title: 'Unable to display the total',
                  message: 'Please review the individual expense balances.',
                );
              }
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Total outstanding'),
                            const SizedBox(height: 8),
                            Text(
                              Money(total.toInt()).formatted,
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 12),
                            ref
                                .watch(creditPaidMonthProvider)
                                .when(
                                  data: (paid) => Text(
                                    'Credit payments this month: ${Money(paid).formatted}',
                                  ),
                                  loading: () => const Text(
                                    'Loading monthly credit payments…',
                                  ),
                                  error: (_, _) => TextButton(
                                    onPressed: () =>
                                        ref.invalidate(creditPaidMonthProvider),
                                    child: const Text(
                                      'Retry monthly credit total',
                                    ),
                                  ),
                                ),
                            const SizedBox(height: 10),
                            const Text(
                              'Record full or partial payments when money is actually paid.',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (records.isEmpty)
                      const StatusPanel(
                        icon: Icons.task_alt,
                        title: 'All settled',
                        message: 'There are no outstanding credit expenses.',
                      ),
                    for (final group in groups.values) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.first.vendorName ?? 'No vendor assigned',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            if (group.first.vendorId != null)
                              TextButton.icon(
                                onPressed: _openingStatement
                                    ? null
                                    : () => _statement(group.first.vendorId!),
                                icon: const Icon(Icons.picture_as_pdf_outlined),
                                label: Text(
                                  _openingStatement
                                      ? 'Preparing statement…'
                                      : 'Share payment statement',
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (final record in group)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            children: [
                              ExpenseListCard(
                                record: record,
                                showCreator: true,
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Purchased ${expenseDateLabel(record.date)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall,
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: _openingPayment
                                        ? null
                                        : () => _pay(record),
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 48),
                                    ),
                                    child: const Text('Record payment'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 10),
                    ],
                  ],
                ),
              );
            },
          ),
    );
  }
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.record, required this.entry});
  final ExpenseRecord record;
  final ExpenseEntryContext entry;
  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  final _form = GlobalKey<FormState>(), _identity = ExpenseRequestIdentity();
  late final TextEditingController _amount;
  final _notes = TextEditingController();
  late String _date;
  String _mode = 'cash';
  String? _error;
  bool _saving = false, _saved = false;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: amountInput(widget.record.outstandingPaise),
    );
    _date = widget.entry.businessDates.first;
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _saved || !_form.currentState!.validate()) return;
    final amount = Money.parse(_amount.text).paise;
    if (ref.read(profileProvider).asData?.value?.role != UserRole.admin) {
      setState(() => _error = 'Administrator access is required.');
      return;
    }
    final values = {
      'expense': widget.record.id,
      'date': _date,
      'amount': amount,
      'mode': _mode,
      'notes': _notes.text.trim(),
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(expenseRepositoryProvider)
          .pay(
            CreditPaymentDraft(
              id: _identity.forValues(values),
              expenseId: widget.record.id,
              date: _date,
              amountPaise: amount,
              mode: _mode,
              notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            ),
          );
      if (!mounted) return;
      setState(() => _saved = true);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      ref.read(financialChangesProvider.notifier).changed();
      unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment recorded. The balance has been updated.'),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = expenseError(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving || _saved,
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Record payment',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close payment entry',
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(widget.record.description),
              const SizedBox(height: 8),
              Text(
                'Outstanding ${Money(widget.record.outstandingPaise).formatted}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              TextFormField(
                key: const Key('credit-payment-amount'),
                controller: _amount,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount paid (₹)',
                  prefixText: '₹ ',
                ),
                validator: (value) {
                  try {
                    final amount = Money.parse(value ?? '').paise;
                    if (amount <= 0) {
                      return 'Enter an amount greater than zero.';
                    }
                    if (amount > widget.record.outstandingPaise) {
                      return 'Payment cannot exceed the outstanding amount.';
                    }
                  } on FormatException {
                    return 'Enter an amount with up to two decimal places.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              const Text(
                'Payment date',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final date in {...widget.entry.businessDates, _date})
                    ChoiceChip(
                      label: Text(expenseDateLabel(date)),
                      selected: _date == date,
                      onSelected: _saving
                          ? null
                          : (_) => setState(() => _date = date),
                    ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving
                      ? null
                      : () async {
                          final selected = await showDatePicker(
                            context: context,
                            firstDate: DateTime.parse(widget.record.date),
                            lastDate: DateTime.parse(
                              widget.entry.businessDates.first,
                            ),
                            initialDate: DateTime.parse(_date),
                          );
                          if (mounted && selected != null) {
                            setState(() => _date = BusinessDay.label(selected));
                          }
                        },
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Choose an older payment date'),
                ),
              ),
              if (!widget.entry.businessDates.contains(_date))
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'The payment date must be reopened in Day end before you can record this payment.',
                  ),
                ),
              const SizedBox(height: 8),
              PaymentModeChoices(
                value: _mode,
                enabled: !_saving,
                onChanged: (mode) => setState(() => _mode = mode),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _notes,
                enabled: !_saving,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
                maxLines: 2,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              PressMotion(
                enabled: !_saving,
                child: FilledButton.icon(
                  key: const Key('save-credit-payment'),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    _saving ? 'Recording payment…' : 'Record payment',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'This payment contributes to the selected payment date’s accounts.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
