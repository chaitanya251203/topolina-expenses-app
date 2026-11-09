import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/accounting/money.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/status_panel.dart';
import '../authentication/auth_repository.dart';
import '../expenses/expense_repository.dart';
import '../reconciliation/business_date_selector.dart';
import '../reconciliation/finance_repository.dart';

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key, this.initialDate});
  final String? initialDate;
  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _form = GlobalKey<FormState>();
  final _expected = TextEditingController(),
      _cash = TextEditingController(),
      _online = TextEditingController(),
      _other = TextEditingController(),
      _notes = TextEditingController();
  String? _date, _loadedDate, _error;
  DaySummary? _loadedSummary;
  bool _busy = false, _dirty = false, _saved = false;

  @override
  void dispose() {
    for (final controller in [_expected, _cash, _online, _other, _notes]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _input(int value) =>
      '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
  void _fill(DaySummary day) {
    if (_loadedDate == day.businessDate &&
        (_dirty || identical(_loadedSummary, day))) {
      return;
    }
    _expected.text = day.expectedPaise == null
        ? ''
        : _input(day.expectedPaise!);
    _cash.text = _input(day.cashPaise);
    _online.text = _input(day.onlinePaise);
    _other.text = _input(day.otherPaise);
    _notes.text = day.notes ?? '';
    _loadedDate = day.businessDate;
    _loadedSummary = day;
    _dirty = false;
  }

  Future<void> _changeDate(String date) async {
    if (date == _date || _busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard unsaved changes?'),
          content: const Text(
            'Your current sales changes have not been saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard changes'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    setState(() {
      _date = date;
      _loadedDate = null;
      _loadedSummary = null;
      _error = null;
      _saved = false;
    });
  }

  int? get _collections {
    try {
      return Reconciliation(
        expected: const Money(0),
        cash: Money.parse(_cash.text),
        online: Money.parse(_online.text),
        other: Money.parse(_other.text),
        paid: const Money(0),
      ).collectionsPaise;
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (_collections == null) {
      setState(() => _error = 'The total collections amount is too large.');
      return;
    }
    FocusScope.of(context).unfocus();
    final draft = SalesDraft(
      businessDate: _date!,
      expectedPaise: Money.parse(_expected.text).paise,
      cashPaise: Money.parse(_cash.text).paise,
      onlinePaise: Money.parse(_online.text).paise,
      otherPaise: Money.parse(_other.text).paise,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
    );
    setState(() {
      _busy = true;
      _error = null;
      _saved = false;
    });
    try {
      await ref.read(financeRepositoryProvider).saveSales(draft);
      if (!mounted) return;
      ref.read(financialChangesProvider.notifier).changed();
      setState(() {
        _dirty = false;
        _saved = true;
      });
    } catch (error) {
      if (mounted) setState(() => _error = financeErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _amount(
    String label,
    String key,
    TextEditingController controller,
    bool enabled,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey(key),
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(labelText: label, prefixText: '₹ '),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      onChanged: (_) => setState(() {
        _dirty = true;
        _saved = false;
      }),
      validator: (value) {
        try {
          Money.parse(value ?? '');
          return null;
        } on FormatException catch (error) {
          return error.message;
        }
      },
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
        appBar: AppBar(title: const Text('Daily sales')),
        body: const StatusPanel(
          icon: Icons.lock_outline,
          title: 'Administrator access',
          message: 'Daily sales are managed by your cafe administrator.',
        ),
      );
    }
    final entry = ref.watch(financialEntryContextProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily sales'),
        actions: [
          IconButton(
            tooltip: 'Refresh sales',
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
      body: entry.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => StatusPanel(
          icon: Icons.wifi_off_outlined,
          title: 'Unable to load sales',
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
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => StatusPanel(
                  icon: Icons.wifi_off_outlined,
                  title: 'Unable to load this day',
                  message: financeErrorMessage(error),
                  action: FilledButton(
                    onPressed: () => ref.invalidate(daySummaryProvider(_date!)),
                    child: const Text('Try again'),
                  ),
                ),
                data: (day) {
                  _fill(day);
                  final editable = day.canEdit(entry) && !_busy;
                  return SafeArea(
                    child: Form(
                      key: _form,
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          BusinessDateSelector(
                            selected: _date!,
                            entry: entry,
                            enabled: !_busy,
                            onChanged: _changeDate,
                          ),
                          const SizedBox(height: 20),
                          if (!day.canEdit(entry)) ...[
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      day.isClosed
                                          ? 'This day is closed'
                                          : 'The entry window has ended',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Reopen this business date with a reason on the day-end screen before making changes.',
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () =>
                                          context.push('/day-end?date=$_date'),
                                      child: const Text('Go to day end'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          Text(
                            'Expected sales',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text('Enter the sales total from Petpooja.'),
                          const SizedBox(height: 16),
                          _amount(
                            'Petpooja sales total',
                            'sales-expected',
                            _expected,
                            editable,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Actual collections',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Enter the collections remaining after expenses.',
                          ),
                          const SizedBox(height: 16),
                          _amount(
                            'Cash collections',
                            'sales-cash',
                            _cash,
                            editable,
                          ),
                          _amount(
                            'Online / bank collections',
                            'sales-online',
                            _online,
                            editable,
                          ),
                          _amount(
                            'Other collections',
                            'sales-other',
                            _other,
                            editable,
                          ),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Total actual collections'),
                                  const SizedBox(height: 8),
                                  AnimatedSwitcher(
                                    duration:
                                        MediaQuery.disableAnimationsOf(context)
                                        ? Duration.zero
                                        : const Duration(milliseconds: 180),
                                    child: Text(
                                      _collections == null
                                          ? 'Check the collection amounts'
                                          : Money(_collections!).formatted,
                                      key: ValueKey(_collections),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          TextFormField(
                            key: const ValueKey('sales-notes'),
                            controller: _notes,
                            enabled: editable,
                            decoration: const InputDecoration(
                              labelText: 'Notes (optional)',
                            ),
                            maxLines: 3,
                            onChanged: (_) => setState(() {
                              _dirty = true;
                              _saved = false;
                            }),
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
                          if (_saved) ...[
                            const SizedBox(height: 16),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                'Sales saved.',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          PressMotion(
                            enabled: editable,
                            child: FilledButton(
                              onPressed: editable ? _save : null,
                              child: _busy
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        semanticsLabel: 'Saving sales',
                                      ),
                                    )
                                  : const Text('Save sales'),
                            ),
                          ),
                          const SizedBox(height: 16),
                          OutlinedButton(
                            onPressed: _busy
                                ? null
                                : () => context.push('/day-end?date=$_date'),
                            child: const Padding(
                              padding: EdgeInsets.all(14),
                              child: Text('Review day end'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
        },
      ),
    );
  }
}
