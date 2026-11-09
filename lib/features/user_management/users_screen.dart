import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/widgets/entry_dialog.dart';
import '../expenses/expense_repository.dart';
import '../staff/staff_repository.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final client = Supabase.instance.client;
  late Future<List<JsonRow>> future;
  @override
  void initState() {
    super.initState();
    refresh();
  }

  void refresh() {
    setState(() {
      future = client.rpc('list_users').then(rows);
    });
  }

  Future<void> accountAction(JsonRow? r, {bool reset = false}) async {
    final identity = ExpenseRequestIdentity();
    final ok = await showEntryForm(
      context,
      title: r == null
          ? 'Create waiter account'
          : reset
          ? 'Reset waiter password'
          : 'Edit waiter account',
      fields: [
        if (!reset)
          EntryField('name', 'Full name', value: r?['full_name'] ?? ''),
        if (r == null) const EntryField('email', 'Email address'),
        if (r == null || reset)
          const EntryField(
            'password',
            'Temporary password',
            kind: EntryKind.password,
            help: 'At least 8 characters. Ask the waiter to change it after signing in.',
          ),
        if (r != null && !reset)
          EntryField(
            'active',
            'Account status',
            value: r['active'] ? 'true' : 'false',
            choices: const {'true': 'Active', 'false': 'Inactive'},
          ),
      ],
      save: (v) async {
        if (r != null && !reset) {
          await client.rpc(
            'update_waiter',
            params: {
              'p_user_id': r['id'],
              'p_name': v['name'],
              'p_active': v['active'] == 'true',
            },
          );
          return;
        }
        if (v['password']!.length < 8) {
          throw const ExpenseValidationException(
            'Use at least 8 characters for the password.',
          );
        }
        try {
          final response = await client.functions.invoke(
            'manage-users',
            body: {
              'action': reset ? 'reset' : 'create',
              'email': v['email'],
              'name': v['name'],
              'password': v['password'],
              'user_id': r?['id'],
              'request_id': identity.forValues(v),
            },
          );
          if (response.status != 200) {
            throw const ExpenseValidationException(
              'Unable to complete this account action.',
            );
          }
        } on FunctionException catch (e) {
          throw ExpenseValidationException(
            e.details is Map
                ? (e.details as Map)['message']?.toString() ??
                      'Account service is unavailable.'
                : 'Account service is unavailable. Check your connection and try again.',
          );
        }
      },
    );
    if (ok == true) refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Users & permissions'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: refresh,
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
              onPressed: refresh,
              child: const Text('Unable to load accounts. Retry'),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(22),
          children: [
            FilledButton.icon(
              onPressed: () => accountAction(null),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Create waiter account'),
            ),
            const SizedBox(height: 18),
            const Text(
              'Staff records track salaries. App accounts control who can sign in. Waiters share the expense permissions below.',
            ),
            const SizedBox(height: 18),
            for (final r in s.requireData)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r['full_name'],
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(r['email'] ?? ''),
                      Text(
                        '${r['role_code'] == 'admin' ? 'Administrator' : 'Waiter'} · ${r['active'] ? 'Active' : 'Inactive'}',
                      ),
                      if (r['role_code'] == 'waiter')
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: () => accountAction(r),
                              child: const Text('Edit account'),
                            ),
                            TextButton(
                              onPressed: () => accountAction(r, reset: true),
                              child: const Text('Reset password'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            const _PermissionSettings(),
          ],
        );
      },
    ),
  );
}

class _PermissionSettings extends StatefulWidget {
  const _PermissionSettings();
  @override
  State<_PermissionSettings> createState() => _PermissionSettingsState();
}

class _PermissionSettingsState extends State<_PermissionSettings> {
  Set<String>? enabled;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final data = await Supabase.instance.client
          .from('role_permissions')
          .select('permission_code')
          .eq('role_code', 'waiter');
      if (mounted) {
        setState(
          () =>
              enabled = {for (final r in data) r['permission_code'] as String},
        );
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load permissions.');
    }
  }

  Future<void> change(String code, bool value) async {
    setState(() => busy = true);
    try {
      await Supabase.instance.client.rpc(
        'set_waiter_permission',
        params: {'p_code': code, 'p_enabled': value},
      );
      await load();
    } catch (e) {
      if (mounted) setState(() => error = expenseError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: Column(
      children: [
        const ListTile(
          title: Text('Waiter permissions'),
          subtitle: Text(
            'Changes apply to every waiter immediately on the server.',
          ),
        ),
        if (error != null) TextButton(onPressed: load, child: Text(error!)),
        for (final p in const {
          'expenses.create': 'Enter expenses',
          'expenses.read_own': 'View own current-day expenses',
        }.entries)
          SwitchListTile(
            title: Text(p.value),
            value: enabled?.contains(p.key) ?? false,
            onChanged: busy || enabled == null ? null : (v) => change(p.key, v),
          ),
      ],
    ),
  );
}

class PasswordScreen extends ConsumerWidget {
  const PasswordScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('Your password')),
    body: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose a password only you know. It is stored securely by Supabase Authentication.',
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            icon: const Icon(Icons.lock_outline),
            label: const Text('Change password'),
            onPressed: () async {
              final ok = await showEntryForm(
                context,
                title: 'Change password',
                fields: const [
                  EntryField(
                    'current',
                    'Current password',
                    kind: EntryKind.password,
                  ),
                  EntryField('new', 'New password', kind: EntryKind.password),
                  EntryField(
                    'confirm',
                    'Confirm new password',
                    kind: EntryKind.password,
                  ),
                ],
                save: (v) async {
                  if (v['new']!.length < 8 || v['new'] != v['confirm']) {
                    throw const ExpenseValidationException(
                      'Passwords must match and contain at least 8 characters.',
                    );
                  }
                  final client = Supabase.instance.client;
                  final email = client.auth.currentUser?.email;
                  if (email == null) {
                    throw const ExpenseValidationException(
                      'Sign in again to change your password.',
                    );
                  }
                  try {
                    await client.auth.signInWithPassword(
                      email: email,
                      password: v['current']!,
                    );
                    await client.auth.updateUser(
                      UserAttributes(password: v['new']!),
                    );
                  } on AuthException catch (e) {
                    throw ExpenseValidationException(e.message);
                  }
                },
              );
              if (ok == true && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Password updated.')),
                );
              }
            },
          ),
        ],
      ),
    ),
  );
}
