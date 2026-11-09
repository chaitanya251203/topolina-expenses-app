import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounting/money.dart';
import '../../core/time/business_day.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/status_panel.dart';
import '../authentication/auth_repository.dart';
import 'expense_repository.dart';
import 'expense_widgets.dart';

class ExpenseFormScreen extends ConsumerStatefulWidget {
  const ExpenseFormScreen({super.key});
  @override
  ConsumerState<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends ConsumerState<ExpenseFormScreen> {
  final _form = GlobalKey<FormState>();
  final _description = TextEditingController(),
      _amount = TextEditingController();
  final _quantity = TextEditingController(text: '1'),
      _rate = TextEditingController();
  final _unit = TextEditingController(),
      _partial = TextEditingController(),
      _notes = TextEditingController();
  final _identity = ExpenseRequestIdentity();
  String? _date, _category, _item, _vendor, _error;
  String _paymentStatus = 'paid', _paymentMode = 'cash';
  bool _calculated = false, _saving = false, _saved = false;

  @override
  void initState() {
    super.initState();
    ref.invalidate(entryContextProvider);
  }

  @override
  void dispose() {
    for (final controller in [
      _description,
      _amount,
      _quantity,
      _rate,
      _unit,
      _partial,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  int? get _total {
    try {
      return _calculated
          ? Money.calculate(
              quantity: _quantity.text,
              rate: Money.parse(_rate.text),
            ).paise
          : Money.parse(_amount.text).paise;
    } on FormatException {
      return null;
    }
  }

  String? _amountValidator(String? value) {
    try {
      if (Money.parse(value ?? '').paise <= 0) {
        return 'Enter an amount greater than zero.';
      }
    } on FormatException {
      return 'Enter an amount with up to two decimal places.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_saving || _saved || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    // The long form uses a lazy list; validate selected masters even when their
    // FormFields have scrolled out of the viewport.
    final entry = ref.read(entryContextProvider).asData?.value;
    if (entry == null ||
        _category == null ||
        !entry.categories.any((choice) => choice.id == _category)) {
      setState(() => _error = 'Choose an available expense category.');
      return;
    }
    if (_vendor != null &&
        !entry.vendors.any((choice) => choice.id == _vendor)) {
      setState(() => _error = 'Choose an available vendor, or select None.');
      return;
    }
    if (_item != null &&
        !entry.items.any(
          (choice) => choice.id == _item && choice.categoryId == _category,
        )) {
      setState(() => _error = 'Choose an available item, or select None.');
      return;
    }
    final total = _total;
    if (total == null || total <= 0) {
      setState(() => _error = 'Check the amount, quantity and rate.');
      return;
    }
    try {
      final paid = _paymentStatus == 'credit'
          ? 0
          : _paymentStatus == 'paid'
          ? total
          : Money.parse(_partial.text).paise;
      if (_paymentStatus == 'partial' && (paid <= 0 || paid >= total)) {
        setState(
          () => _error = 'A partial payment must be greater than zero and less than the expense amount.',
        );
        return;
      }
      final values = <String, dynamic>{
        'date': _date,
        'category': _category,
        'description': _description.text.trim(),
        'amount': total,
        'paid': paid,
        'mode': paid > 0 ? _paymentMode : null,
        'quantity': _calculated ? _quantity.text.trim() : null,
        'rate': _calculated ? Money.parse(_rate.text).paise : null,
        'unit': _calculated && _unit.text.trim().isNotEmpty
            ? _unit.text.trim()
            : null,
        'item': _item,
        'vendor': _vendor,
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      };
      final draft = ExpenseDraft(
        id: _identity.forValues(values),
        date: _date!,
        categoryId: _category!,
        description: _description.text.trim(),
        amountPaise: total,
        paidPaise: paid,
        paymentMode: paid > 0 ? _paymentMode : null,
        quantity: values['quantity'] as String?,
        unit: values['unit'] as String?,
        ratePaise: values['rate'] as int?,
        itemId: _item,
        vendorId: _vendor,
        notes: values['notes'] as String?,
      );
      draft.validate();
      setState(() {
        _saving = true;
        _error = null;
      });
      await ref.read(expenseRepositoryProvider).create(draft);
      if (!mounted) return;
      setState(() => _saved = true);
      // Let PopScope observe the committed state before popping this route.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      ref.read(financialChangesProvider.notifier).changed();
      unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense saved to the cafe ledger.')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = expenseError(error);
        });
      }
    }
  }

  Future<void> _chooseOlderDate(ExpenseEntryContext entry) async {
    final latest = DateTime.parse(entry.businessDates.first);
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: latest,
      initialDate: DateTime.parse(_date ?? entry.businessDates.first),
    );
    if (mounted && selected != null) {
      setState(() => _date = BusinessDay.label(selected));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving || _saved,
    child: Scaffold(
      appBar: AppBar(title: const Text('Add expense')),
      body: ref
          .watch(entryContextProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => StatusPanel(
              icon: Icons.wifi_off_outlined,
              title: 'Unable to open the expense form',
              message: 'Check your connection and try again.',
              action: FilledButton(
                onPressed: () => ref.invalidate(entryContextProvider),
                child: const Text('Try again'),
              ),
            ),
            data: (entry) {
              if (entry.categories.isEmpty || entry.businessDates.isEmpty) {
                return const StatusPanel(
                  icon: Icons.category_outlined,
                  title: 'No categories available',
                  message: 'Ask your administrator to add or activate an expense category.',
                );
              }
              _date ??= entry.businessDates.first;
              final admin =
                  ref.watch(profileProvider).asData?.value?.role ==
                  UserRole.admin;
              final selectedItems = entry.items
                  .where((item) => item.categoryId == _category)
                  .toList();
              return Form(
                key: _form,
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    const Text(
                      'Record it once. Everyone stays up to date.',
                      style: TextStyle(fontSize: 15, height: 1.5),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Business date',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final date in {...entry.businessDates, _date!})
                          ChoiceChip(
                            selected: _date == date,
                            label: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                '${date == entry.businessDates.first ? 'Today · ' : ''}${expenseDateLabel(date)}',
                              ),
                            ),
                            onSelected: _saving
                                ? null
                                : (_) => setState(() => _date = date),
                          ),
                      ],
                    ),
                    if (admin)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _saving
                              ? null
                              : () => _chooseOlderDate(entry),
                          icon: const Icon(Icons.calendar_month_outlined),
                          label: const Text('Choose an older date'),
                        ),
                      ),
                    if (admin && !entry.businessDates.contains(_date))
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Older dates must be reopened in Day end before an expense can be added.',
                        ),
                      ),
                    const SizedBox(height: 16),
                    ExpenseChoiceField(
                      label: 'Category',
                      categoryIcons: true,
                      required: true,
                      choices: entry.categories,
                      value: _category,
                      enabled: !_saving,
                      onChanged: (value) => setState(() {
                        _category = value;
                        _item = null;
                      }),
                    ),
                    if (selectedItems.isNotEmpty || _item != null) ...[
                      const SizedBox(height: 16),
                      ExpenseChoiceField(
                        label: 'Item',
                        choices: selectedItems,
                        value: _item,
                        enabled: !_saving,
                        onChanged: (value) => setState(() {
                          _item = value;
                          if (value != null) {
                            final item = selectedItems.firstWhere(
                              (item) => item.id == value,
                            );
                            _description.text = item.name;
                            _unit.text = item.defaultUnit ?? '';
                            if (item.defaultRatePaise != null &&
                                item.defaultRatePaise! > 0) {
                              _rate.text = amountInput(item.defaultRatePaise!);
                              _calculated = true;
                            }
                          }
                        }),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const Key('expense-description'),
                      controller: _description,
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 2,
                      maxLength: 500,
                      decoration: const InputDecoration(
                        labelText: 'Description *',
                        hintText: 'What was this expense for?',
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a short expense description.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text('Enter amount'),
                          ),
                          selected: !_calculated,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _calculated = false),
                        ),
                        ChoiceChip(
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text('Quantity × rate'),
                          ),
                          selected: _calculated,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _calculated = true),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!_calculated)
                      TextFormField(
                        key: const Key('expense-amount'),
                        controller: _amount,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount (₹) *',
                          prefixText: '₹ ',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: _amountValidator,
                      ),
                    if (_calculated) ...[
                      TextFormField(
                        key: const Key('expense-quantity'),
                        controller: _quantity,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Quantity *',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: (value) =>
                            !RegExp(r'^(?:[0-9]{1,10})(?:\.[0-9]{1,6})?$')
                                .hasMatch(value?.trim() ?? '')
                            ? 'Enter a positive quantity with up to six decimal places.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('expense-rate'),
                        controller: _rate,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Rate (₹) *',
                          prefixText: '₹ ',
                        ),
                        onChanged: (_) => setState(() {}),
                        validator: _amountValidator,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _unit,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Unit',
                          hintText: 'kg, litre, packet…',
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Expense total'),
                            const SizedBox(height: 8),
                            Text(
                              _total == null
                                  ? 'Enter the amount above'
                                  : Money(_total!).formatted,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Payment',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in const {
                          'paid': 'Paid now',
                          'partial': 'Partly paid',
                          'credit': 'On credit',
                        }.entries)
                          ChoiceChip(
                            label: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(option.value),
                            ),
                            selected: _paymentStatus == option.key,
                            onSelected: _saving
                                ? null
                                : (_) => setState(
                                    () => _paymentStatus = option.key,
                                  ),
                          ),
                      ],
                    ),
                    if (_paymentStatus == 'partial') ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('expense-partial'),
                        controller: _partial,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Amount paid now (₹) *',
                          prefixText: '₹ ',
                        ),
                        validator: _amountValidator,
                      ),
                    ],
                    if (_paymentStatus != 'credit') ...[
                      const SizedBox(height: 14),
                      PaymentModeChoices(
                        value: _paymentMode,
                        enabled: !_saving,
                        onChanged: (mode) =>
                            setState(() => _paymentMode = mode),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'The payment will be recorded on ${expenseDateLabel(_date!)}.',
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      const Text(
                        'No payment will be recorded. This expense stays outstanding until it is paid.',
                      ),
                    ],
                    const SizedBox(height: 24),
                    ExpenseChoiceField(
                      label: 'Vendor',
                      choices: entry.vendors,
                      value: _vendor,
                      enabled: !_saving,
                      emptyMessage: 'No vendors have been added. You can save this expense without a vendor.',
                      onChanged: (value) => setState(() => _vendor = value),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notes,
                      enabled: !_saving,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    PressMotion(
                      enabled: !_saving,
                      child: FilledButton.icon(
                        key: const Key('save-expense'),
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(
                          _saving ? 'Saving expense…' : 'Save expense',
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Saved entries are immediately available in the cafe ledger.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          ),
    ),
  );
}
