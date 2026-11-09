import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/accounting/money.dart';
import '../../core/categories/category_visuals.dart';
import '../../core/widgets/entry_dialog.dart';
import '../expenses/expense_repository.dart';
import '../staff/staff_repository.dart';
import 'report_repository.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  Map<String, dynamic>? filters;
  Future<JsonRow>? future;
  bool busy = false;
  String? initialError;
  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      final entry = await ref.read(expenseRepositoryProvider).entryContext();
      if (mounted) {
        final today = entry.businessDates.first;
        setState(() {
          filters = {'p_from': '${today.substring(0, 7)}-01', 'p_to': today};
          future = ref.read(reportRepositoryProvider).load(filters!);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          initialError = expenseError(e);
        });
      }
    }
  }

  void reload() {
    if (filters == null) {
      initialize();
    } else {
      setState(() {
        future = ref.read(reportRepositoryProvider).load(filters!);
      });
    }
  }

  Future<void> chooseFilters() async {
    try {
      final results = await Future.wait([
        ref.read(expenseRepositoryProvider).entryContext(),
        ref.read(staffRepositoryProvider).staff(),
      ]);
      if (!mounted) return;
      final entry = results[0] as ExpenseEntryContext,
          staff = results[1] as List<JsonRow>;
      final ok = await showEntryForm(
        context,
        title: 'Report filters',
        action: 'Show report',
        fields: [
          EntryField(
            'p_from',
            'From date',
            value: filters!['p_from'],
            kind: EntryKind.date,
          ),
          EntryField(
            'p_to',
            'Through date',
            value: filters!['p_to'],
            kind: EntryKind.date,
          ),
          EntryField(
            'p_category',
            'Category',
            value: filters!['p_category'] ?? '',
            required: false,
            choices: {
              '': 'All categories',
              for (final c in entry.categories) c.id: c.name,
            },
          ),
          EntryField(
            'p_vendor',
            'Vendor',
            value: filters!['p_vendor'] ?? '',
            required: false,
            choices: {
              '': 'All vendors',
              for (final v in entry.vendors) v.id: v.name,
            },
          ),
          EntryField(
            'p_staff',
            'Staff member',
            value: filters!['p_staff'] ?? '',
            required: false,
            choices: {
              '': 'All staff and other expenses',
              for (final s in staff) s['id']: s['full_name'],
            },
          ),
          EntryField(
            'p_mode',
            'Payment mode',
            value: filters!['p_mode'] ?? '',
            required: false,
            choices: const {
              '': 'All modes',
              'cash': 'Cash',
              'online': 'Bank / online',
              'other': 'Other',
            },
          ),
          EntryField(
            'p_status',
            'Payment status at end date',
            value: filters!['p_status'] ?? '',
            required: false,
            choices: const {
              '': 'All statuses',
              'paid': 'Paid',
              'partially_paid': 'Partially paid',
              'outstanding': 'Outstanding',
            },
          ),
        ],
        save: (v) async {
          final params = {
            for (final e in v.entries) e.key: e.value.isEmpty ? null : e.value,
          };
          final data = await ref.read(reportRepositoryProvider).load(params);
          if (mounted) {
            setState(() {
              filters = params;
              future = Future.value(data);
            });
          }
        },
      );
      if (ok == true && mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(expenseError(e))));
      }
    }
  }

  Future<void> export(JsonRow r) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final saved = await FilePicker.saveFile(
        fileName: 'Topolina-report-${r['from']}-${r['to']}.csv',
        mimeType: 'text/csv',
        bytes: reportCsv(r, filters!),
      );
      if (saved != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Report saved.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to save the file. Choose a writable folder and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reports'),
      actions: [
        IconButton(
          tooltip: 'Refresh reports',
          onPressed: reload,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: initialError != null
        ? Center(
            child: FilledButton(
              onPressed: () {
                setState(() => initialError = null);
                initialize();
              },
              child: const Text('Unable to load report. Retry'),
            ),
          )
        : future == null
        ? const Center(child: CircularProgressIndicator())
        : FutureBuilder(
            future: future,
            builder: (c, s) {
              if (s.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (s.hasError) {
                return Center(
                  child: FilledButton(
                    onPressed: reload,
                    child: const Text('Unable to load report. Retry'),
                  ),
                );
              }
              final r = s.requireData, daily = rows(r['daily']);
              Widget total(String label, String key) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  title: Text(label),
                  trailing: Text(
                    Money(jsonPaise(r[key])).formatted,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );
              return ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  Text(
                    '${expenseDateLabel(r['from'])} – ${expenseDateLabel(r['to'])}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: chooseFilters,
                        icon: const Icon(Icons.filter_list),
                        label: const Text('Dates & filters'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy ? null : () => export(r),
                        icon: const Icon(Icons.download_outlined),
                        label: Text(busy ? 'Saving…' : 'Export CSV'),
                      ),
                    ],
                  ),
                  if (filters!.entries.any(
                    (e) =>
                        !['p_from', 'p_to'].contains(e.key) && e.value != null,
                  ))
                    const Text(
                      'Expense filters applied. Sales and reconciliation still show the complete day.',
                    ),
                  const SizedBox(height: 18),
                  Text(
                    'Sales & collections',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'All categories. Net collections entered after expenses.',
                  ),
                  total('Expected sales', 'expected_paise'),
                  total('Cash collected', 'cash_paise'),
                  total('Bank / online collected', 'online_paise'),
                  total('Other collected', 'other_paise'),
                  const SizedBox(height: 20),
                  Text(
                    'Expense activity',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Selected filters. Outstanding includes older purchases, as of the report end date.',
                  ),
                  total('Expenses incurred', 'incurred_paise'),
                  total('Expenses paid', 'paid_paise'),
                  total('Outstanding at end date', 'outstanding_paise'),
                  total('Linked salary payments', 'salary_paid_paise'),
                  const SizedBox(height: 24),
                  Text(
                    'Daily payments',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 210,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: math.max(
                          MediaQuery.sizeOf(context).width - 44,
                          daily.length * 34.0,
                        ),
                        child: BarChart(
                          BarChartData(
                            borderData: FlBorderData(show: false),
                            gridData: const FlGridData(show: false),
                            titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (v, m) => Text(
                                    '${DateTime.parse(daily[v.toInt()]['business_date']).day}',
                                  ),
                                ),
                              ),
                            ),
                            barTouchData: BarTouchData(
                              touchTooltipData: BarTouchTooltipData(
                                fitInsideHorizontally: true,
                                getTooltipItem: (group, gi, rod, ri) =>
                                    BarTooltipItem(
                                      '${expenseDateLabel(daily[gi]['business_date'])}\n${Money(jsonPaise(daily[gi]['filtered_paid_paise'])).formatted}',
                                      const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                              ),
                            ),
                            barGroups: [
                              for (var i = 0; i < daily.length; i++)
                                BarChartGroupData(
                                  x: i,
                                  barRods: [
                                    BarChartRodData(
                                      toY:
                                          jsonPaise(
                                            daily[i]['filtered_paid_paise'],
                                          ).toDouble() /
                                          100,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      width: 16,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (final section in ['categories', 'vendors']) ...[
                    Text(
                      section == 'categories' ? 'By category' : 'By vendor',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    if (rows(r[section]).isEmpty)
                      const Text('No matching expenses.'),
                    for (final group in rows(r[section]))
                      Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: Icon(
                            section == 'categories'
                                ? CategoryVisuals.icon(
                                    group['name'],
                                    group['icon_key'],
                                  )
                                : Icons.storefront_outlined,
                          ),
                          title: Text(group['name']),
                          subtitle: Text(
                            'Incurred ${Money(jsonPaise(group['incurred_paise'])).formatted}\nPaid ${Money(jsonPaise(group['paid_paise'])).formatted}\nPending ${Money(jsonPaise(group['outstanding_paise'])).formatted}',
                          ),
                        ),
                      ),
                    const SizedBox(height: 22),
                  ],
                  Text(
                    'Daily reconciliation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    'Complete accounts, including every payment mode and category.',
                  ),
                  const SizedBox(height: 12),
                  for (final d in daily)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        title: Text(expenseDateLabel(d['business_date'])),
                        subtitle: Text(
                          d['expected_paise'] == null
                              ? 'Sales not entered'
                              : 'Expected ${Money(jsonPaise(d['expected_paise'])).formatted}\nCollected ${Money(jsonPaise(d['collections_paise'])).formatted} · Paid ${Money(jsonPaise(d['paid_paise'])).formatted}\nDifference ${Money(jsonPaise(d['difference_paise'])).formatted} · ${d['state']}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () =>
                            context.push('/day-end?date=${d['business_date']}'),
                      ),
                    ),
                  const SizedBox(height: 30),
                ],
              );
            },
          ),
  );
}
