import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/accounting/money.dart';
import '../../core/time/business_day.dart';
import '../../core/widgets/entry_dialog.dart';
import '../../core/widgets/status_panel.dart';
import '../credit/credit_screen.dart';
import '../expenses/expense_repository.dart';
import '../expenses/expense_widgets.dart';
import 'staff_repository.dart';

class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});
  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  String? month;
  bool opening = false;
  void changed() => ref.read(financialChangesProvider.notifier).changed();
  Future<void> guarded(Future<void> Function() work) async {
    if (opening) return;
    setState(() => opening = true);
    try {
      await work();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(expenseError(e))));
      }
    } finally {
      if (mounted) setState(() => opening = false);
    }
  }

  Future<void> editStaff([JsonRow? r]) => guarded(() async {
    final entry = await ref.read(entryContextProvider.future);
    if (!mounted) return;
    final id = r?['id'] ?? const Uuid().v4();
    final ok = await showEntryForm(
      context,
      title: r == null ? 'Add staff member' : 'Edit staff member',
      fields: [
        EntryField('code', 'Staff ID', value: r?['staff_code'] ?? ''),
        EntryField('name', 'Full name', value: r?['full_name'] ?? ''),
        EntryField(
          'designation',
          'Designation',
          value: r?['designation'] ?? '',
        ),
        EntryField(
          'joining',
          'Joining date',
          value: r?['joining_date'] ?? entry.businessDates.first,
          kind: EntryKind.date,
        ),
        EntryField(
          'contact',
          'Contact number',
          value: r?['contact_number'] ?? '',
          required: false,
        ),
        EntryField(
          'salary',
          'Monthly salary (₹)',
          value: r?['default_salary_paise'] == null
              ? ''
              : amountInput(jsonPaise(r!['default_salary_paise'])),
          kind: EntryKind.money,
          required: false,
        ),
        EntryField(
          'active',
          'Status',
          value: r?['active'] == false ? 'false' : 'true',
          choices: const {'true': 'Active', 'false': 'Inactive'},
        ),
      ],
      save: (v) => ref.read(staffRepositoryProvider).save({
        'p_id': id,
        'p_code': v['code'],
        'p_name': v['name'],
        'p_designation': v['designation'],
        'p_joining_date': v['joining'],
        'p_contact': v['contact'],
        'p_salary_paise': v['salary']!.isEmpty
            ? null
            : Money.parse(v['salary']!).paise,
        'p_active': v['active'] == 'true',
      }),
    );
    if (ok == true) changed();
  });
  Future<void> createSalary(List<JsonRow> staff) => guarded(() async {
    final entry = await ref.read(entryContextProvider.future);
    if (!mounted) return;
    final identity = ExpenseRequestIdentity();
    final active = staff.where((s) => s['active'] == true).toList();
    if (active.isEmpty) {
      throw const ExpenseValidationException(
        'Add an active staff member first.',
      );
    }
    final categories = {for (final c in entry.categories) c.id: c.name};
    final salaryCategory =
        entry.categories
            .where((c) => c.name.toLowerCase().contains('salary'))
            .firstOrNull
            ?.id ??
        entry.categories.firstOrNull?.id ??
        '';
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (c) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(22),
            child: Text(
              'Add salary record',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_card),
            title: const Text('Create unpaid salary'),
            subtitle: const Text('Record payments separately when paid'),
            onTap: () => Navigator.pop(c, 'new'),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Link existing expense'),
            subtitle: const Text('Reuse a salary expense already entered'),
            onTap: () => Navigator.pop(c, 'link'),
          ),
          const SizedBox(height: 22),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    ExpenseRecord? linked;
    if (selected == 'link') {
      String date = entry.businessDates.first;
      await showEntryForm(
        context,
        title: 'Find existing expense',
        fields: [
          EntryField('date', 'Expense date', value: date, kind: EntryKind.date),
        ],
        action: 'Find expenses',
        save: (v) async {
          date = v['date']!;
        },
      );
      if (!mounted) return;
      final expenses = await ref
          .read(expenseRepositoryProvider)
          .list(from: date, to: date);
      if (!mounted) return;
      linked = await showModalBottomSheet<ExpenseRecord>(
        context: context,
        useSafeArea: true,
        builder: (c) => SizedBox(
          height: 440,
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(22),
                child: Text('Choose the original salary expense'),
              ),
              if (expenses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(22),
                  child: Text('No expenses found for this date.'),
                ),
              for (final e in expenses)
                ListTile(
                  title: Text(e.description),
                  subtitle: Text(
                    '${e.categoryName} · ${Money(e.amountPaise).formatted}',
                  ),
                  onTap: () => Navigator.pop(c, e),
                ),
            ],
          ),
        ),
      );
      if (linked == null || !mounted) return;
    }
    final existing = linked;
    final selectedStaff = await showModalBottomSheet<JsonRow>(
      context: context,
      useSafeArea: true,
      builder: (c) => SizedBox(
        height: 400,
        child: ListView(
          children: [
            const Padding(
              padding: EdgeInsets.all(22),
              child: Text('Choose a staff member'),
            ),
            for (final s in active)
              ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(s['full_name']),
                subtitle: Text('${s['staff_code']} · ${s['designation']}'),
                onTap: () => Navigator.pop(c, s),
              ),
          ],
        ),
      ),
    );
    if (selectedStaff == null || !mounted) return;
    final ok = await showEntryForm(
      context,
      title: existing == null ? 'New monthly salary' : 'Link salary expense',
      explanation: existing == null
          ? 'This creates an unpaid salary. Use Record payment when cash or money is actually paid.'
          : 'This links the original expense and its payment history. No second expense is created.',
      fields: [
        EntryField(
          'staff',
          'Staff member',
          value: selectedStaff['id'],
          choices: {
            selectedStaff['id']:
                '${selectedStaff['full_name']} · ${selectedStaff['staff_code']}',
          },
          readOnly: true,
        ),
        EntryField(
          'month',
          'Salary month',
          value: month!,
          kind: EntryKind.date,
          help: 'Any day in the selected month is accepted.',
        ),
        EntryField(
          'date',
          'Expense date',
          value: existing?.date ?? entry.businessDates.first,
          kind: EntryKind.date,
          readOnly: existing != null,
          help: 'Older dates must first be reopened in Day end.',
        ),
        EntryField(
          'category',
          'Expense category',
          value: existing?.categoryId ?? salaryCategory,
          choices: {
            ...categories,
            if (existing != null) existing.categoryId: existing.categoryName,
          },
          readOnly: existing != null,
        ),
        EntryField(
          'amount',
          'Salary amount (₹)',
          value: existing != null
              ? amountInput(existing.amountPaise)
              : selectedStaff['default_salary_paise'] == null
              ? ''
              : amountInput(jsonPaise(selectedStaff['default_salary_paise'])),
          kind: EntryKind.money,
          readOnly: existing != null,
          help: 'Confirm the amount for the selected staff member.',
        ),
        const EntryField('notes', 'Notes', required: false),
      ],
      save: (v) {
        final params = <String, dynamic>{
          'p_staff_id': v['staff'],
          'p_month': '${v['month']!.substring(0, 7)}-01',
          'p_date': v['date'],
          'p_category_id': v['category'],
          'p_amount_paise': Money.parse(v['amount']!).paise,
          'p_existing_expense_id': existing?.id,
          'p_notes': v['notes'],
        };
        return ref.read(staffRepositoryProvider).salary({
          ...params,
          'p_id': identity.forValues(params),
        });
      },
    );
    if (ok == true) changed();
  });
  @override
  Widget build(BuildContext context) {
    final entry = ref.watch(entryContextProvider);
    final entryDate = entry.asData?.value.businessDates.first;
    if (month == null && entryDate != null) {
      month = '${entryDate.substring(0, 7)}-01';
    }
    final staff = ref.watch(staffProvider);
    final salaries = month == null
        ? const AsyncValue<List<JsonRow>>.loading()
        : ref.watch(payrollProvider(month!));
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Staff & salaries'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Salaries'),
              Tab(text: 'Staff members'),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: changed,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: TabBarView(
          children: [
            salaries.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => StatusPanel(
                icon: Icons.wifi_off,
                title: 'Unable to load salaries',
                message: 'Check your connection and try again.',
                action: FilledButton(
                  onPressed: changed,
                  child: const Text('Retry'),
                ),
              ),
              data: (list) => ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_month),
                    label: Text(
                      expenseDateLabel(month!).replaceFirst('1 ', ''),
                    ),
                    onPressed: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.parse(month!),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (date != null) {
                        setState(
                          () => month =
                              '${BusinessDay.label(date).substring(0, 7)}-01',
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pending ${Money(list.fold<int>(0, (sum, s) => sum + jsonPaise(s['outstanding_paise']))).formatted}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Paid ${Money(list.fold<int>(0, (sum, s) => sum + jsonPaise(s['paid_paise']))).formatted}',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: opening || !staff.hasValue
                        ? null
                        : () => createSalary(staff.requireValue),
                    icon: const Icon(Icons.add),
                    label: const Text('Add salary record'),
                  ),
                  const SizedBox(height: 18),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(22),
                      child: Text(
                        'No salary records for this month. Add one to track dues and payments.',
                      ),
                    ),
                  for (final s in list)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              s['staff_name'],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text('${s['designation']} · ${s['staff_code']}'),
                            const SizedBox(height: 12),
                            Text(
                              'Salary ${Money(jsonPaise(s['amount_paise'])).formatted}',
                            ),
                            Text(
                              'Paid ${Money(jsonPaise(s['paid_paise'])).formatted} · Pending ${Money(jsonPaise(s['outstanding_paise'])).formatted}',
                            ),
                            TextButton(
                              onPressed: () =>
                                  showExpenseDetails(context, salaryExpense(s)),
                              child: const Text('View payment history'),
                            ),
                            if (jsonPaise(s['outstanding_paise']) > 0)
                              FilledButton(
                                onPressed: opening
                                    ? null
                                    : () => guarded(() async {
                                        ref.invalidate(entryContextProvider);
                                        final e = await ref.read(
                                          entryContextProvider.future,
                                        );
                                        if (!context.mounted) return;
                                        await showLedgerPayment(
                                          context,
                                          salaryExpense(s),
                                          e,
                                        );
                                      }),
                                child: const Text('Record payment'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
            staff.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(
                child: Text('Unable to load staff. Pull refresh to retry.'),
              ),
              data: (list) => ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  FilledButton.icon(
                    onPressed: opening ? null : () => editStaff(),
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Add staff member'),
                  ),
                  const SizedBox(height: 18),
                  if (list.isEmpty)
                    const Text(
                      'Add your cafe team. Staff records are separate from app login accounts.',
                    ),
                  for (final s in list)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: const Icon(Icons.badge_outlined),
                        title: Text(s['full_name']),
                        subtitle: Text(
                          '${s['staff_code']} · ${s['designation']}\n${s['active'] ? 'Active' : 'Inactive'}',
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: opening ? null : () => editStaff(s),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
