import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/accounting/money.dart';
import '../../core/widgets/motion.dart';
import '../authentication/auth_repository.dart';
import 'dashboard_repository.dart';

class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, String path) async {
    await context.push(path);
    if (context.mounted) ref.invalidate(dashboardProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).asData?.value;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final admin = profile.role == UserRole.admin;
    final overview = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'TOPOLINA',
          style: TextStyle(
            letterSpacing: 3,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh overview',
            onPressed: () => ref.invalidate(dashboardProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            await ref.read(dashboardProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.all(22),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Text(
                'Welcome, ${profile.name.split(' ').first}.',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                admin
                    ? 'Your cafe at a glance'
                    : 'Your expenses for the business day',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 22),
              PressMotion(
                child: FilledButton.icon(
                  onPressed: () => _open(context, ref, '/expenses/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Add expense'),
                ),
              ),
              const SizedBox(height: 20),
              overview.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(28),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Unable to load today’s overview',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Check your connection and try again. Your saved entries are kept in your cafe workspace.',
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => ref.invalidate(dashboardProvider),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (snapshot) {
                  final day = snapshot.day;
                  final hasSales = day['has_sales'] == true;
                  final state = day['state'] as String? ?? 'not_started';
                  final stateLabel = switch (state) {
                    'closed' => 'Closed',
                    'reopened' => 'Reopened',
                    'open' => 'In progress',
                    _ => 'Not started',
                  };
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              snapshot.date,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          Chip(
                            label: Text(stateLabel),
                            avatar: Icon(
                              state == 'closed'
                                  ? Icons.lock_outline
                                  : Icons.calendar_today_outlined,
                              size: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (admin) ...[
                        _Metric(
                          label: 'Expected sales',
                          value: hasSales
                              ? Money(day['expected_paise'] as int).formatted
                              : 'Not entered',
                          primary: true,
                        ),
                        const SizedBox(height: 12),
                        _Metric(
                          label: 'Net collections',
                          value: hasSales
                              ? Money(
                                  (day['cash_paise'] as int) +
                                      (day['online_paise'] as int) +
                                      (day['other_paise'] as int),
                                ).formatted
                              : 'Not entered',
                        ),
                        const SizedBox(height: 12),
                        _Metric(
                          label: 'Expenses paid today',
                          value: Money((day['paid_paise'] as int?) ?? 0)
                              .formatted,
                        ),
                        const SizedBox(height: 12),
                        _Metric(
                          label: 'Outstanding credit',
                          value: Money(snapshot.total('outstanding_paise'))
                              .formatted,
                        ),
                        if (hasSales) ...[
                          const SizedBox(height: 12),
                          _Metric(
                            label: (day['difference_paise'] as int) == 0
                                ? 'Reconciliation • Balanced'
                                : (day['difference_paise'] as int) > 0
                                ? 'Reconciliation • Short'
                                : 'Reconciliation • Excess',
                            value: Money(day['difference_paise'] as int)
                                .formatted,
                          ),
                        ],
                        const SizedBox(height: 24),
                        const Text(
                          'This month',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Metric(
                          label: 'Expected sales',
                          value: Money(snapshot.total('monthly_expected_paise'))
                              .formatted,
                        ),
                        const SizedBox(height: 10),
                        _Metric(
                          label: 'Expenses incurred',
                          value: Money(snapshot.total('monthly_incurred_paise'))
                              .formatted,
                        ),
                        const SizedBox(height: 10),
                        _Metric(
                          label: 'Expenses paid',
                          value: Money(snapshot.total('monthly_paid_paise'))
                              .formatted,
                        ),
                      ] else ...[
                        _Metric(
                          label: 'Your submitted entries',
                          value: '${snapshot.total('own_expense_count')}',
                          primary: true,
                        ),
                        const SizedBox(height: 12),
                        _Metric(
                          label: 'Your expenses today',
                          value: Money(snapshot.total('own_incurred_paise'))
                              .formatted,
                        ),
                        const SizedBox(height: 12),
                        _Metric(
                          label: 'Paid with your entries',
                          value: Money(snapshot.total('own_paid_paise'))
                              .formatted,
                        ),
                      ],
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Quick actions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              _Action(
                icon: Icons.receipt_long_outlined,
                title: admin ? 'View daily expenses' : 'My submitted expenses',
                subtitle: admin
                    ? 'Admin and waiter entries in one ledger'
                    : 'Review your own entries',
                onTap: () => _open(context, ref, '/expenses'),
              ),
              if (admin) ...[
                _Action(
                  icon: Icons.point_of_sale_outlined,
                  title: 'Sales & collections',
                  subtitle: 'Enter the day’s sales and net collections',
                  onTap: () => _open(context, ref, '/sales'),
                ),
                _Action(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Credit payments',
                  subtitle: 'Track dues and record full or partial payments',
                  onTap: () => _open(context, ref, '/credit'),
                ),
                _Action(
                  icon: Icons.fact_check_outlined,
                  title: 'Day-end reconciliation',
                  subtitle: 'Review payments and close the business day',
                  onTap: () => _open(context, ref, '/day-end'),
                ),
              ],
              _Action(
                icon: Icons.category_outlined,
                title: 'Expense categories',
                subtitle: 'Browse available categories',
                onTap: () => context.push('/categories'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.primary = false,
  });
  final String label, value;
  final bool primary;
  @override
  Widget build(BuildContext context) => Card(
    color: primary ? TopolinaTheme.forest : Colors.white,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: primary ? const Color(0xFFE1E8E2) : null,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 26,
              color: primary ? Colors.white : TopolinaTheme.forest,
            ),
          ),
        ],
      ),
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    ),
  );
}
