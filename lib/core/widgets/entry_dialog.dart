import 'package:flutter/material.dart';

import '../../features/expenses/expense_repository.dart';
import '../accounting/money.dart';
import '../time/business_day.dart';

enum EntryKind { text, money, date, password }

class EntryField {
  const EntryField(
    this.key,
    this.label, {
    this.value = '',
    this.required = true,
    this.kind = EntryKind.text,
    this.choices,
    this.help,
    this.readOnly = false,
  });
  final String key, label, value;
  final bool required, readOnly;
  final EntryKind kind;
  final Map<String, String>? choices;
  final String? help;
}

Future<bool?> showEntryForm(
  BuildContext context, {
  required String title,
  required List<EntryField> fields,
  required Future<void> Function(Map<String, String>) save,
  String action = 'Save',
  String? explanation,
}) => Navigator.of(context).push<bool>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _EntryPage(
      title: title,
      fields: fields,
      save: save,
      action: action,
      explanation: explanation,
    ),
  ),
);

class _EntryPage extends StatefulWidget {
  const _EntryPage({
    required this.title,
    required this.fields,
    required this.save,
    required this.action,
    this.explanation,
  });
  final String title, action;
  final String? explanation;
  final List<EntryField> fields;
  final Future<void> Function(Map<String, String>) save;
  @override
  State<_EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<_EntryPage> {
  final form = GlobalKey<FormState>();
  late final values = {
    for (final f in widget.fields) f.key: TextEditingController(text: f.value),
  };
  bool busy = false, saved = false;
  String? error;
  @override
  void dispose() {
    for (final v in values.values) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.save({
        for (final f in widget.fields)
          f.key: f.kind == EntryKind.password
              ? values[f.key]!.text
              : values[f.key]!.text.trim(),
      });
      if (!mounted) return;
      setState(() => saved = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = expenseError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy || saved,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        automaticallyImplyLeading: !busy,
      ),
      body: SafeArea(
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(22),
            children: [
              if (widget.explanation != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: Text(
                    widget.explanation!,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              for (final f in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: f.choices != null
                      ? DropdownButtonFormField<String>(
                          initialValue:
                              f.choices!.containsKey(values[f.key]!.text)
                              ? values[f.key]!.text
                              : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: f.label,
                            helperText: f.help,
                            helperMaxLines: 3,
                          ),
                          items: f.choices!.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy || f.readOnly
                              ? null
                              : (v) => values[f.key]!.text = v ?? '',
                          validator: (v) =>
                              f.required && (v == null || v.isEmpty)
                              ? 'Choose ${f.label.toLowerCase()}.'
                              : null,
                        )
                      : TextFormField(
                          controller: values[f.key],
                          enabled: !busy,
                          readOnly: f.readOnly || f.kind == EntryKind.date,
                          obscureText: f.kind == EntryKind.password,
                          autocorrect: f.kind != EntryKind.password,
                          enableSuggestions: f.kind != EntryKind.password,
                          keyboardType: f.kind == EntryKind.money
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : TextInputType.text,
                          decoration: InputDecoration(
                            labelText: f.label,
                            helperText: f.help,
                            helperMaxLines: 3,
                            suffixIcon: f.kind == EntryKind.date
                                ? const Icon(Icons.calendar_month_outlined)
                                : null,
                          ),
                          onTap: f.kind != EntryKind.date || f.readOnly
                              ? null
                              : () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        DateTime.tryParse(
                                          values[f.key]!.text,
                                        ) ??
                                        DateTime.now(),
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked != null) {
                                    values[f.key]!.text = BusinessDay.label(
                                      picked,
                                    );
                                  }
                                },
                          validator: (v) {
                            if (f.required && (v ?? '').trim().isEmpty) {
                              return 'Enter ${f.label.toLowerCase()}.';
                            }
                            if (f.kind == EntryKind.money &&
                                (v ?? '').trim().isNotEmpty) {
                              try {
                                Money.parse(v!);
                              } catch (_) {
                                return 'Enter a valid amount with up to two decimal places.';
                              }
                            }
                            return null;
                          },
                        ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: busy ? null : submit,
                icon: busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Text(busy ? 'Saving…' : widget.action),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
