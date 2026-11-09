import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../authentication/auth_repository.dart';
import '../dashboard/dashboard_repository.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).asData?.value;
    final admin = profile?.role == UserRole.admin;
    Widget link(IconData icon, String label, String path) => Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        onTap: () async {
          await context.push(path);
          if (context.mounted) ref.invalidate(dashboardProvider);
        },
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Your workspace')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            Text(
              profile?.name ?? '',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(admin ? 'Administrator' : 'Waiter'),
            const SizedBox(height: 24),
            if (admin) ...[
              link(Icons.badge_outlined, 'Staff & salaries', '/staff'),
              const SizedBox(height: 10),
              link(Icons.insights_outlined, 'Reports & export', '/reports'),
              const SizedBox(height: 10),
              link(
                Icons.manage_accounts_outlined,
                'App users & permissions',
                '/users',
              ),
              const SizedBox(height: 10),
              link(Icons.backup_outlined, 'Backups & restore', '/backups'),
              const SizedBox(height: 10),
              link(Icons.history_outlined, 'Audit history', '/audit'),
              const SizedBox(height: 10),
              link(Icons.tune, 'Categories, vendors & items', '/masters'),
              const SizedBox(height: 10),
              link(
                Icons.point_of_sale_outlined,
                'Sales & collections',
                '/sales',
              ),
              const SizedBox(height: 10),
              link(
                Icons.account_balance_wallet_outlined,
                'Credit ledger',
                '/credit',
              ),
              const SizedBox(height: 10),
            ],
            link(
              Icons.category_outlined,
              'Browse expense categories',
              '/categories',
            ),
            const SizedBox(height: 24),
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Business day: midnight to midnight. The previous day remains available until 1 a.m. Closed days require an administrator to reopen them.',
                  style: TextStyle(height: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 24),
            link(Icons.lock_outline, 'Change your password', '/password'),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await ref.read(authRepositoryProvider).signOut();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Unable to sign out. Please try again.'),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.logout),
              label: const Padding(
                padding: EdgeInsets.all(14),
                child: Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
