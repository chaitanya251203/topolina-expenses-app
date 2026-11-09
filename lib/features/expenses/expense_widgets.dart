import 'package:flutter/material.dart';

import '../../core/accounting/money.dart';
import '../../core/categories/category_visuals.dart';
import 'expense_repository.dart';
import '../audit/correction_actions.dart';

class ExpenseChoiceField extends StatelessWidget {
  const ExpenseChoiceField({
    super.key,
    required this.label,
    required this.choices,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.enabled = true,
    this.categoryIcons = false,
    this.emptyMessage = 'No options are available.',
  });
  final String label, emptyMessage;
  final List<ExpenseChoice> choices;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool required, enabled, categoryIcons;

  @override
  Widget build(BuildContext context) {
    final matches = choices.where((choice) => choice.id == value);
    final selectedName = matches.isEmpty ? null : matches.first.name;
    return FormField<String>(
      key: ValueKey('$label/$value'),
      initialValue: value,
      validator: (entry) {
        if (required && entry == null) {
          return 'Choose a ${label.toLowerCase()}.';
        }
        if (entry != null && !choices.any((choice) => choice.id == entry)) {
          return 'Choose an available ${label.toLowerCase()}${required ? '.' : ' or None.'}';
        }
        return null;
      },
      builder: (state) => Semantics(
        button: true,
        enabled: enabled,
        label: 'Choose ${label.toLowerCase()}',
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: !enabled
              ? null
              : () async {
                  final selected = await showModalBottomSheet<String>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (context) => _ChoiceSheet(
                      label: label,
                      choices: choices,
                      allowNone: !required,
                      emptyMessage: emptyMessage,
                      categoryIcons: categoryIcons,
                    ),
                  );
                  if (context.mounted && selected != null) {
                    onChanged(selected.isEmpty ? null : selected);
                  }
                },
          child: InputDecorator(
            isEmpty: selectedName == null,
            decoration: InputDecoration(
              labelText: required ? '$label *' : label,
              floatingLabelBehavior: FloatingLabelBehavior.always,
              enabled: enabled,
              errorText: state.errorText,
              suffixIcon: const Icon(Icons.expand_more),
              prefixIcon: categoryIcons
                  ? Icon(
                      CategoryVisuals.icon(
                        selectedName ?? '',
                        matches.isEmpty ? null : matches.first.iconKey,
                      ),
                    )
                  : null,
            ),
            child: Text(
              selectedName == null
                  ? 'Select ${label.toLowerCase()}'
                  : categoryIcons
                  ? CategoryVisuals.readableName(selectedName)
                  : selectedName,
              style: selectedName == null
                  ? TextStyle(color: Theme.of(context).hintColor)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChoiceSheet extends StatefulWidget {
  const _ChoiceSheet({
    required this.label,
    required this.choices,
    required this.allowNone,
    required this.emptyMessage,
    required this.categoryIcons,
  });
  final String label, emptyMessage;
  final List<ExpenseChoice> choices;
  final bool allowNone, categoryIcons;
  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final visible = widget.choices
        .where((c) => c.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose ${widget.label.toLowerCase()}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close choices',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Search ${widget.label.toLowerCase()}',
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.allowNone)
                    ListTile(
                      leading: const Icon(Icons.remove_circle_outline),
                      title: const Text('None'),
                      onTap: () => Navigator.pop(context, ''),
                    ),
                  if (visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.choices.isEmpty
                            ? widget.emptyMessage
                            : 'No matching options. Try another name.',
                      ),
                    ),
                  ...visible.map(
                    (choice) => ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 4,
                      ),
                      leading: widget.categoryIcons
                          ? CircleAvatar(
                              backgroundColor: const Color(0xFFE8EFE8),
                              child: Icon(
                                CategoryVisuals.icon(
                                  choice.name,
                                  choice.iconKey,
                                ),
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            )
                          : null,
                      title: Text(
                        widget.categoryIcons
                            ? CategoryVisuals.readableName(choice.name)
                            : choice.name,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, choice.id),
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

class PaymentModeChoices extends StatelessWidget {
  const PaymentModeChoices({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final mode in ['cash', 'online', 'other'])
        ChoiceChip(
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(paymentModeLabel(mode)),
          ),
          selected: value == mode,
          onSelected: !enabled ? null : (_) => onChanged(mode),
        ),
    ],
  );
}

class ExpenseStatusBadge extends StatelessWidget {
  const ExpenseStatusBadge({super.key, required this.record});
  final ExpenseRecord record;
  @override
  Widget build(BuildContext context) {
    final paid = record.outstandingPaise == 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: paid ? const Color(0xFFE5EFE8) : const Color(0xFFF6E8CF),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        paid
            ? 'Paid'
            : record.paidPaise > 0
            ? 'Partly paid'
            : 'On credit',
        style: TextStyle(
          fontSize: 12,
          color: paid ? const Color(0xFF193F34) : const Color(0xFF6A4A17),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class ExpenseListCard extends StatelessWidget {
  const ExpenseListCard({
    super.key,
    required this.record,
    this.onTap,
    this.showCreator = false,
  });
  final ExpenseRecord record;
  final VoidCallback? onTap;
  final bool showCreator;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap ?? () => showExpenseDetails(context, record),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  CategoryVisuals.icon(
                    record.categoryName,
                    record.categoryIconKey,
                  ),
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    CategoryVisuals.readableName(record.categoryName),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              record.description,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (record.vendorName != null) ...[
              const SizedBox(height: 4),
              Text(record.vendorName!),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  Money(record.amountPaise).formatted,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                ExpenseStatusBadge(record: record),
              ],
            ),
            if (record.outstandingPaise > 0) ...[
              const SizedBox(height: 8),
              Text('Remaining ${Money(record.outstandingPaise).formatted}'),
            ],
            if (showCreator) ...[
              const SizedBox(height: 10),
              Text(
                'Entered by ${record.createdByName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

Future<void> showExpenseDetails(
  BuildContext context,
  ExpenseRecord record,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: .75,
    minChildSize: .4,
    maxChildSize: .95,
    builder: (context, controller) => ListView(
      controller: controller,
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Expense details',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Close details',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          record.description,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        ExpenseStatusBadge(record: record),
        const SizedBox(height: 20),
        _DetailLine('Business date', expenseDateLabel(record.date)),
        _DetailLine('Category', record.categoryName),
        if (record.vendorName != null)
          _DetailLine('Vendor', record.vendorName!),
        if (record.quantity != null)
          _DetailLine(
            'Quantity',
            '${record.quantity} ${record.unit ?? ''}'.trim(),
          ),
        if (record.ratePaise != null)
          _DetailLine('Rate', Money(record.ratePaise!).formatted),
        _DetailLine('Expense amount', Money(record.amountPaise).formatted),
        _DetailLine('Paid so far', Money(record.paidPaise).formatted),
        _DetailLine('Outstanding', Money(record.outstandingPaise).formatted),
        _DetailLine('Entered by', record.createdByName),
        CorrectionActions(expense: record),
        if (record.notes?.isNotEmpty == true) ...[
          const Divider(height: 32),
          const Text('Notes', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(record.notes!),
        ],
        const Divider(height: 32),
        Text('Payment history', style: Theme.of(context).textTheme.titleMedium),
        if (record.payments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No payment has been recorded.'),
          ),
        ...record.payments.map(
          (payment) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Money(payment.amountPaise).formatted,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${expenseDateLabel(payment.date)} · ${paymentModeLabel(payment.mode)}',
                ),
                if (payment.notes?.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(payment.notes!),
                ],
                CorrectionActions(expense: record, payment: payment),
              ],
            ),
          ),
        ),
      ],
    ),
  ),
);

class _DetailLine extends StatelessWidget {
  const _DetailLine(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value),
      ],
    ),
  );
}
