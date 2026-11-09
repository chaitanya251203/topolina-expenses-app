import 'package:flutter/material.dart';

import '../../core/time/business_day.dart';
import 'finance_repository.dart';

class BusinessDateSelector extends StatelessWidget {
  const BusinessDateSelector({
    super.key,
    required this.selected,
    required this.entry,
    required this.onChanged,
    this.enabled = true,
  });
  final String selected;
  final FinancialEntryContext entry;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Business date', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  MaterialLocalizations.of(context)
                      .formatFullDate(DateTime.parse(selected)),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Choose business date',
                onPressed: enabled
                    ? () async {
                        final result = await showDatePicker(
                          context: context,
                          initialDate: DateTime.parse(selected),
                          firstDate: DateTime(1900),
                          lastDate: DateTime.parse(entry.today),
                        );
                        if (result != null) {
                          onChanged(BusinessDay.label(result));
                        }
                      }
                    : null,
                icon: const Icon(Icons.calendar_month_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var index = 0; index < entry.businessDates.length; index++)
                ChoiceChip(
                  label: Text(
                    index == 0 ? 'Today' : 'Yesterday · until 1 a.m.',
                  ),
                  selected: selected == entry.businessDates[index],
                  onSelected: enabled
                      ? (_) => onChanged(entry.businessDates[index])
                      : null,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
