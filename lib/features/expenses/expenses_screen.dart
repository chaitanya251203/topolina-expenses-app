import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/accounting/money.dart';
import '../../core/time/business_day.dart';
import '../../core/widgets/status_panel.dart';
import '../authentication/auth_repository.dart';
import 'expense_repository.dart';
import 'expense_widgets.dart';

class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  String? _date;
  Future<void> _refresh() async {
    ref.invalidate(entryContextProvider);
    if (_date != null) ref.invalidate(expensesProvider(_date!));
    try {
      await ref.read(entryContextProvider.future);
    } catch (_) {
      /* Provider displays the retry state. */
    }
  }

  Future<void> _add() async {
    await context.push<bool>('/expenses/new');
    if (mounted) await _refresh();
  }

  Future<void> _pickDate(ExpenseEntryContext entry) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.parse(entry.businessDates.first),
      initialDate: DateTime.parse(_date ?? entry.businessDates.first),
    );
    if (mounted && selected != null) {
      setState(() => _date = BusinessDay.label(selected));
    }
  }

  @override
  Widget build(BuildContext context) {
    final admin =
        ref.watch(profileProvider).asData?.value?.role == UserRole.admin;
    return Scaffold(
      appBar: AppBar(
        title: Text(admin ? 'Expenses' : 'My expenses'),
        actions: [
          IconButton(
            tooltip: 'Refresh expenses',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton:
          ref.watch(profileProvider).asData?.value?.can('expenses.create') ==
              false
          ? null
          : FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add expense'),
            ),
      body:
          ref.watch(profileProvider).asData?.value?.can('expenses.read_own') ==
              false
          ? const StatusPanel(
              icon: Icons.lock_outline,
              title: 'Expense history is disabled',
              message: 'Your administrator manages access to your current-day entries.',
            )
          : ref
                .watch(entryContextProvider)
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => StatusPanel(
                    icon: Icons.wifi_off_outlined,
                    title: 'Unable to load expenses',
                    message: 'Check your connection and try again.',
                    action: FilledButton(
                      onPressed: _refresh,
                      child: const Text('Try again'),
                    ),
                  ),
                  data: (entry) {
                    if (entry.businessDates.isEmpty) {
                      return const StatusPanel(
                        icon: Icons.calendar_month_outlined,
                        title: 'Business date unavailable',
                        message: 'Refresh your account and try again.',
                      );
                    }
                    if (_date == null ||
                        (!admin && !entry.businessDates.contains(_date))) {
                      _date = entry.businessDates.first;
                    }
                    return SafeArea(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  admin ? 'Every entry in one shared ledger.' : 'Your entries for the selected business date.',
                                ),
                                const SizedBox(height: 14),
                                if (admin)
                                  OutlinedButton.icon(
                                    onPressed: () => _pickDate(entry),
                                    icon: const Icon(
                                      Icons.calendar_month_outlined,
                                    ),
                                    label: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      child: Text(expenseDateLabel(_date!)),
                                    ),
                                  )
                                else
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final date in entry.businessDates)
                                        ChoiceChip(
                                          selected: _date == date,
                                          label: Text(expenseDateLabel(date)),
                                          onSelected: (_) =>
                                              setState(() => _date = date),
                                        ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ref
                                .watch(expensesProvider(_date!))
                                .when(
                                  loading: () => const Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                  error: (_, _) => StatusPanel(
                                    icon: Icons.wifi_off_outlined,
                                    title: 'Unable to load entries',
                                    message: 'Your saved entries are safe. Check your connection and try again.',
                                    action: FilledButton(
                                      onPressed: () => ref.invalidate(
                                        expensesProvider(_date!),
                                      ),
                                      child: const Text('Try again'),
                                    ),
                                  ),
                                  data: (records) => RefreshIndicator(
                                    onRefresh: _refresh,
                                    child: ListView(
                                      physics:
                                          const AlwaysScrollableScrollPhysics(),
                                      padding: const EdgeInsets.fromLTRB(
                                        20,
                                        0,
                                        20,
                                        100,
                                      ),
                                      children: [
                                        if (records.isEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 50,
                                            ),
                                            child: StatusPanel(
                                              icon: Icons.receipt_long_outlined,
                                              title:
                                                  'No expenses for this date',
                                              message: admin
                                                  ? 'Add an expense to start the day’s ledger.'
                                                  : 'Your submitted expenses will appear here.',
                                              action: FilledButton.icon(
                                                onPressed: _add,
                                                icon: const Icon(Icons.add),
                                                label: const Text(
                                                  'Add expense',
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (records.isNotEmpty) ...[
                                          Card(
                                            child: Padding(
                                              padding: const EdgeInsets.all(20),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    '${records.length} ${records.length == 1 ? 'expense' : 'expenses'}',
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    Money(
                                                      _sum(
                                                        records.map(
                                                          (record) => record
                                                              .amountPaise,
                                                        ),
                                                      ),
                                                    ).formatted,
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .headlineSmall
                                                        ?.copyWith(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                    'Expenses incurred on this date',
                                                  ),
                                                  const SizedBox(height: 6),
                                                  const Text(
                                                    'Payments may belong to a different date. Review Day end for amounts paid today.',
                                                    style: TextStyle(
                                                      height: 1.4,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 18),
                                          for (final record in records)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: ExpenseListCard(
                                                record: record,
                                                showCreator: admin,
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

int _sum(Iterable<int> values) {
  final total = values.fold(
    BigInt.zero,
    (sum, value) => sum + BigInt.from(value),
  );
  if (!total.isValidInt) throw RangeError('Expense total is too large.');
  return total.toInt();
}
