import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/entry_dialog.dart';
import '../expenses/expense_repository.dart';
import '../staff/staff_repository.dart';
import 'backup_repository.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});
  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  late Future<JsonRow> future;
  bool busy = false;
  String? message;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    setState(() {
      future = ref.read(backupRepositoryProvider).status();
    });
  }

  Future<void> run(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await work();
      if (mounted) reload();
    } catch (e) {
      if (mounted) setState(() => message = expenseError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export(String id) async {
    final data = await ref.read(backupRepositoryProvider).download(id);
    final saved = await FilePicker.saveFile(
      fileName:
          'Topolina-${data['created_at'].toString().substring(0, 10)}-${id.substring(0, 8)}.topolina.json',
      bytes: BackupCodec.encode(data),
      mimeType: 'application/json',
    );
    if (saved != null && mounted) {
      setState(() => message = 'Backup file saved.');
    }
  }

  Future<void> restoreFile(String project) async {
    final files = await FilePicker.pickFiles();
    if (files.isEmpty) return;
    final bytes = BytesBuilder(copy: false);
    var count = 0;
    await for (final chunk in files.first.readAsByteStream()) {
      count += chunk.length;
      if (count > backupMaxBytes) {
        throw const FormatException(
          'This backup file exceeds the mobile restore limit.',
        );
      }
      bytes.add(chunk);
    }
    final data = BackupCodec.decode(bytes.takeBytes());
    if (data['project_id'] != project) {
      throw const FormatException(
        'Choose a backup from this Topolina Supabase project.',
      );
    }
    if (!mounted) return;
    final ok = await showEntryForm(
      context,
      title: 'Restore backup',
      action: 'Restore cafe data',
      explanation:
          'Restore the cafe ledger to ${data['created_at']}. Current application records will be replaced. A safety snapshot is created first, and audit history is preserved. App users and passwords stay in Supabase Authentication.',
      fields: const [
        EntryField('reason', 'Reason for restoring'),
        EntryField('confirm', 'Type RESTORE to confirm'),
        EntryField(
          'password',
          'Your current password',
          kind: EntryKind.password,
        ),
      ],
      save: (v) async {
        if (v['confirm'] != 'RESTORE') {
          throw const ExpenseValidationException('Type RESTORE to confirm.');
        }
        await ref
            .read(backupRepositoryProvider)
            .restore(data, v['reason']!, v['password']!);
      },
    );
    if (ok == true) {
      ref.read(financialChangesProvider.notifier).changed();
      if (mounted) {
        setState(
          () => message =
              'Cafe data restored. The safety backup is available below.',
        );
      }
    }
  }

  Future<void> configure(JsonRow status) async {
    await showEntryForm(
      context,
      title: 'Automatic backups',
      fields: [
        EntryField(
          'enabled',
          'Automatic backups',
          value: status['enabled'] ? 'true' : 'false',
          choices: const {'true': 'Enabled', 'false': 'Disabled'},
        ),
        EntryField(
          'interval',
          'Frequency',
          value: status['interval_hours'].toString(),
          choices: const {'24': 'Daily', '168': 'Weekly'},
        ),
        EntryField(
          'retention',
          'Number of snapshots to keep',
          value: status['retention'].toString(),
          help: 'Between 2 and 60. Download files to keep longer.',
        ),
      ],
      save: (v) async {
        final count = int.tryParse(v['retention']!);
        if (count == null || count < 2 || count > 60) {
          throw const ExpenseValidationException(
            'Keep between 2 and 60 snapshots.',
          );
        }
        await ref
            .read(backupRepositoryProvider)
            .configure(
              v['enabled'] == 'true',
              int.parse(v['interval']!),
              count,
            );
      },
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Backups & restore'),
        automaticallyImplyLeading: !busy,
        actions: [
          IconButton(
            tooltip: 'Refresh backups',
            onPressed: busy ? null : reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder(
        future: future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (s.hasError) {
            return Center(
              child: FilledButton(
                onPressed: reload,
                child: const Text('Unable to load backups. Retry'),
              ),
            );
          }
          final status = s.requireData, list = rows(status['backups']);
          return ListView(
            padding: const EdgeInsets.all(22),
            children: [
              const Text(
                'Your cafe data lives in Supabase. Reinstalling this app does not erase it. These snapshots protect application records; they do not include Auth accounts, passwords, or the entire Supabase project.',
                style: TextStyle(height: 1.5),
              ),
              const SizedBox(height: 18),
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.cloud_done_outlined),
                  title: Text(
                    list.isEmpty
                        ? 'No successful backup yet'
                        : 'Last backup: ${eventTimeLabel(list.first['created_at'])}',
                  ),
                  subtitle: Text(
                    status['enabled'] && status['scheduler_ready']
                        ? 'Automatic ${status['interval_hours'] == 24 ? 'daily' : 'weekly'} snapshots enabled.'
                        : 'Automatic backups ${status['enabled'] ? 'are awaiting server scheduling.' : 'disabled.'}',
                  ),
                  trailing: IconButton(
                    tooltip: 'Backup settings',
                    onPressed: busy ? null : () => run(() => configure(status)),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() async {
                        final id = await ref
                            .read(backupRepositoryProvider)
                            .create();
                        if (mounted) {
                          setState(
                            () => message = 'Server backup created. Choose Download to save a copy to your phone.',
                          );
                        }
                        if (mounted) await export(id);
                      }),
                icon: const Icon(Icons.backup_outlined),
                label: const Text('Create & download backup'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () => run(() => restoreFile(status['project_id'])),
                icon: const Icon(Icons.restore_outlined),
                label: const Text('Restore from a backup file'),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(message!),
                ),
              const SizedBox(height: 18),
              Text(
                'Server snapshots',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              for (final b in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(b['reason']),
                    subtitle: Text(
                      '${eventTimeLabel(b['created_at'])}\n${(jsonPaise(b['size']) / 1024).toStringAsFixed(1)} KB',
                    ),
                    trailing: IconButton(
                      tooltip: 'Download backup',
                      onPressed: busy ? null : () => run(() => export(b['id'])),
                      icon: const Icon(Icons.download_outlined),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const Text(
                'Downloaded files contain cafe financial data. Store them somewhere you control. Restores accept files from this project, with matching checksums and valid ledger relationships.',
              ),
            ],
          );
        },
      ),
    ),
  );
}
