import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/accounting/money.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/status_panel.dart';
import '../authentication/auth_repository.dart';
import '../expenses/expense_repository.dart';
import 'business_date_selector.dart';
import 'finance_repository.dart';

class DayEndScreen extends ConsumerStatefulWidget {
  const DayEndScreen({super.key, this.initialDate});
  final String? initialDate;
  @override
  ConsumerState<DayEndScreen> createState() => _DayEndScreenState();
}

class _DayEndScreenState extends ConsumerState<DayEndScreen> {
  String? _date, _error, _success;
  bool _busy = false;

  Future<void> _act(DaySummary day, {required bool reopen}) async {
    if (_busy) return;
    final result = await showDialog<String>(
      context: context,
      builder: (_) =>
          _ReasonDialog(reopen: reopen, differencePaise: day.differencePaise),
    );
    if (result == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
    });
    try {
      final repository = ref.read(financeRepositoryProvider);
      if (reopen) {
        await repository.reopenDay(day.businessDate, result);
      } else {
        await repository.closeDay(
          day.businessDate,
          result.isEmpty ? null : result,
        );
      }
      if (!mounted) return;
      ref.read(financialChangesProvider.notifier).changed();
      setState(
        () => _success = reopen
            ? 'Day reopened. Changes will be recorded in the audit history.'
            : 'Business day closed.',
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = financeErrorMessage(error));
        ref.invalidate(daySummaryProvider(day.businessDate));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _line(String label, String value, {bool prominent = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: prominent ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: prominent ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(profileProvider);
    if (profile.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (profile.asData?.value?.role != UserRole.admin ||
        profile.asData?.value?.active != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Day end')),
        body: const StatusPanel(
          icon: Icons.lock_outline,
          title: 'Administrator access',
          message:
              'Day-end reconciliation is managed by your cafe administrator.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Day end'),
        actions: [
          IconButton(
            tooltip: 'Refresh day end',
            onPressed: _busy
                ? null
                : () {
                    ref.invalidate(financialEntryContextProvider);
                    if (_date != null) {
                      ref.invalidate(daySummaryProvider(_date!));
                    }
                  },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ref
          .watch(financialEntryContextProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => StatusPanel(
              icon: Icons.wifi_off_outlined,
              title: 'Unable to load day end',
              message: financeErrorMessage(error),
              action: FilledButton(
                onPressed: () => ref.invalidate(financialEntryContextProvider),
                child: const Text('Try again'),
              ),
            ),
            data: (entry) {
              _date ??= entry.startingDate(widget.initialDate);
              return ref
                  .watch(daySummaryProvider(_date!))
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => StatusPanel(
                      icon: Icons.wifi_off_outlined,
                      title: 'Unable to load this day',
                      message: financeErrorMessage(error),
                      action: FilledButton(
                        onPressed: () =>
                            ref.invalidate(daySummaryProvider(_date!)),
                        child: const Text('Try again'),
                      ),
                    ),
                    data: (day) {
                      final canEdit = day.canEdit(entry);
                      final color =
                          day.differencePaise == null ||
                              day.differencePaise == 0
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error;
                      return SafeArea(
                        child: ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            BusinessDateSelector(
                              selected: _date!,
                              entry: entry,
                              enabled: !_busy,
                              onChanged: (value) => setState(() {
                                _date = value;
                                _error = null;
                                _success = null;
                              }),
                            ),
                            const SizedBox(height: 16),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Chip(
                                avatar: Icon(
                                  day.isClosed
                                      ? Icons.lock_outline
                                      : Icons.access_time,
                                  size: 18,
                                ),
                                label: Text(day.stateLabel),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Daily reconciliation',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    const SizedBox(height: 12),
                                    _line(
                                      'Expected sales',
                                      day.expectedPaise == null
                                          ? 'Not recorded'
                                          : Money(day.expectedPaise!).formatted,
                                      prominent: true,
                                    ),
                                    const Divider(height: 24),
                                    _line(
                                      'Cash collections',
                                      day.hasSales
                                          ? Money(day.cashPaise).formatted
                                          : 'Not recorded',
                                    ),
                                    _line(
                                      'Online / bank collections',
                                      day.hasSales
                                          ? Money(day.onlinePaise).formatted
                                          : 'Not recorded',
                                    ),
                                    _line(
                                      'Other collections',
                                      day.hasSales
                                          ? Money(day.otherPaise).formatted
                                          : 'Not recorded',
                                    ),
                                    _line(
                                      'Total actual collections',
                                      day.hasSales
                                          ? Money(day.collectionsPaise)
                                                .formatted
                                          : 'Not recorded',
                                      prominent: true,
                                    ),
                                    _line(
                                      'Expenses paid this day',
                                      Money(day.paidPaise).formatted,
                                      prominent: true,
                                    ),
                                    const Divider(height: 24),
                                    _line(
                                      'Total accounted',
                                      day.hasSales
                                          ? Money(day.accountedPaise).formatted
                                          : 'Sales needed',
                                      prominent: true,
                                    ),
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(18),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.08),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            day.balanceLabel,
                                            key: const ValueKey(
                                              'balance-status',
                                            ),
                                            style: TextStyle(
                                              color: color,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 18,
                                            ),
                                          ),
                                          if (day.differencePaise != null) ...[
                                            const SizedBox(height: 8),
                                            Text(
                                              Money(day.differencePaise!)
                                                  .formatted,
                                              key: const ValueKey(
                                                'difference-amount',
                                              ),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(color: color),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Expected sales − (actual collections + expenses paid).',
                                      style: TextStyle(height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (!day.hasSales) ...[
                              const SizedBox(height: 16),
                              const Text(
                                'Record the daily sales and collections before closing this day.',
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton(
                                onPressed: _busy
                                    ? null
                                    : () => context.push('/sales?date=$_date'),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text('Enter daily sales'),
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            Text(
                              'Purchases and outstanding amounts',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  children: [
                                    _line(
                                      'Expenses incurred on this date',
                                      Money(day.incurredPaise).formatted,
                                    ),
                                    _line(
                                      'Still unpaid from those expenses',
                                      Money(day.outstandingPaise).formatted,
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Unpaid amounts are not included in the expenses paid above.',
                                      style: TextStyle(height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Payments included',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Only payments made on this business date are included.',
                            ),
                            const SizedBox(height: 12),
                            if (day.payments.isEmpty)
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                    'No expense payments recorded for this date.',
                                  ),
                                ),
                              ),
                            for (final payment in day.payments) ...[
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(18),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        payment.description,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${payment.categoryName} · ${payment.createdByName}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 10),
                                      _line(
                                        _mode(payment.mode),
                                        Money(payment.amountPaise).formatted,
                                        prominent: true,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
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
                            if (_success != null) ...[
                              const SizedBox(height: 12),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _success!,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            if (day.isClosed || !canEdit) ...[
                              Text(
                                day.isClosed
                                    ? 'This day is closed. Its records are locked.'
                                    : 'The ordinary entry window has ended for this date.',
                              ),
                              const SizedBox(height: 12),
                              PressMotion(
                                enabled: !_busy,
                                child: OutlinedButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => _act(day, reopen: true),
                                  icon: const Icon(Icons.lock_open_outlined),
                                  label: const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: Text('Reopen day'),
                                  ),
                                ),
                              ),
                            ] else
                              PressMotion(
                                enabled: !_busy && day.hasSales,
                                child: FilledButton.icon(
                                  onPressed: !_busy && day.hasSales
                                      ? () => _act(day, reopen: false)
                                      : null,
                                  icon: _busy
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.check_circle_outline),
                                  label: const Text('Close business day'),
                                ),
                              ),
                            const SizedBox(height: 20),
                          ],
                        ),
                      );
                    },
                  );
            },
          ),
    );
  }

  String _mode(String value) => switch (value) {
    'cash' => 'Cash payment',
    'online' => 'Online / bank payment',
    _ => 'Other payment',
  };
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.reopen, required this.differencePaise});
  final bool reopen;
  final int? differencePaise;
  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final required = widget.reopen || widget.differencePaise != 0;
    return AlertDialog(
      title: Text(widget.reopen ? 'Reopen this day?' : 'Close this day?'),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.reopen
                    ? 'Enter a reason to unlock this date. The reason is saved in the audit history.'
                    : 'Closing locks this business date. Review the figures and payment entries before continuing.',
              ),
              if (!widget.reopen &&
                  widget.differencePaise != null &&
                  widget.differencePaise != 0) ...[
                const SizedBox(height: 12),
                Text(
                  'Difference: ${Money(widget.differencePaise!).formatted}. Explain the difference to close this day.',
                ),
              ],
              const SizedBox(height: 18),
              TextFormField(
                key: const ValueKey('day-action-reason'),
                controller: _reason,
                decoration: InputDecoration(
                  labelText: required
                      ? 'Reason (required)'
                      : 'Closing note (optional)',
                ),
                maxLines: 3,
                validator: (value) =>
                    required && (value == null || value.trim().isEmpty)
                    ? 'Enter a reason to continue.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_form.currentState!.validate()) {
              Navigator.pop(context, _reason.text.trim());
            }
          },
          child: Text(widget.reopen ? 'Confirm reopen' : 'Confirm close'),
        ),
      ],
    );
  }
}
