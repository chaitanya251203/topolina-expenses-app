import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../expenses/expense_repository.dart';
import '../staff/staff_repository.dart';

class AuditScreen extends StatefulWidget {
  const AuditScreen({super.key});
  @override
  State<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends State<AuditScreen> {
  final entries = <JsonRow>[];
  bool busy = false;
  String? error;
  bool more = true;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = rows(
        await Supabase.instance.client.rpc(
          'get_audit_logs',
          params: {
            'p_before': reset || entries.isEmpty ? null : entries.last['id'],
          },
        ),
      );
      if (mounted) {
        setState(() {
          if (reset) entries.clear();
          entries.addAll(data);
          more = data.length == 50;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = expenseError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Audit history'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          'Every financial correction, void, closing and master-data change retains its actor and original values.',
        ),
        const SizedBox(height: 18),
        for (final r in entries)
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ExpansionTile(
              title: Text('${r['operation']} · ${r['table_name']}'),
              subtitle: Text(
                '${r['actor_name']}\n${eventTimeLabel(r['created_at'])}',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert({
                      'record': r['record_id'],
                      'before': r['before_data'],
                      'after': r['after_data'],
                    }),
                  ),
                ),
              ],
            ),
          ),
        if (error != null) Text(error!),
        if (busy)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(22),
              child: CircularProgressIndicator(),
            ),
          ),
        if (!busy && more)
          OutlinedButton(
            onPressed: load,
            child: Text(error != null ? 'Try again' : 'Load more'),
          ),
      ],
    ),
  );
}
