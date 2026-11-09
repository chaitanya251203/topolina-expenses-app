import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/status_panel.dart';
import '../core/widgets/motion.dart';
import '../features/authentication/auth_repository.dart';
import '../features/authentication/login_screen.dart';
import '../features/dashboard/workspace_screen.dart';
import '../features/categories/categories_screen.dart';
import '../features/expenses/expenses_screen.dart';
import '../features/expenses/expense_form_screen.dart';
import '../features/credit/credit_screen.dart';
import '../features/sales/sales_screen.dart';
import '../features/reconciliation/day_end_screen.dart';
import '../features/masters/masters_screen.dart';
import '../features/settings/more_screen.dart';

class _RouterRefresh extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authUserProvider, (_, _) => refresh.refresh());
  ref.listen(profileProvider, (_, _) => refresh.refresh());
  final router = GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authUserProvider),
          profile = ref.read(profileProvider);
      final path = state.uri.path;
      if (auth.isLoading) return path == '/loading' ? null : '/loading';
      if (auth.hasError) return path == '/access' ? null : '/access';
      if (auth.asData?.value == null) return path == '/login' ? null : '/login';
      if (profile.isLoading) return path == '/loading' ? null : '/loading';
      if (profile.hasError || profile.asData?.value?.active != true) {
        return path == '/access' ? null : '/access';
      }
      if (['/login', '/loading', '/access'].contains(path)) return '/';
      if ([
            '/credit',
            '/sales',
            '/day-end',
            '/masters',
          ].any((route) => path == route || path.startsWith('$route/')) &&
          profile.asData!.value!.role != UserRole.admin) {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        pageBuilder: (context, state) => _page(state, const LoginScreen()),
      ),
      GoRoute(
        path: '/loading',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/access', builder: (_, _) => const _AccessScreen()),
      GoRoute(
        path: '/expenses/new',
        pageBuilder: (_, state) => _page(state, const ExpenseFormScreen()),
      ),
      GoRoute(
        path: '/sales',
        pageBuilder: (_, state) => _page(
          state,
          SalesScreen(initialDate: state.uri.queryParameters['date']),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            _WorkspaceShell(path: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, state) => _page(state, const WorkspaceScreen()),
          ),
          GoRoute(
            path: '/expenses',
            pageBuilder: (_, state) => _page(state, const ExpensesScreen()),
          ),
          GoRoute(
            path: '/credit',
            pageBuilder: (_, state) => _page(state, const CreditScreen()),
          ),
          GoRoute(
            path: '/day-end',
            pageBuilder: (_, state) => _page(
              state,
              DayEndScreen(initialDate: state.uri.queryParameters['date']),
            ),
          ),
          GoRoute(
            path: '/categories',
            pageBuilder: (_, state) => _page(state, const CategoriesScreen()),
          ),
          GoRoute(
            path: '/masters',
            pageBuilder: (_, state) => _page(state, const MastersScreen()),
          ),
          GoRoute(
            path: '/more',
            pageBuilder: (_, state) => _page(state, const MoreScreen()),
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: StatusPanel(
        icon: Icons.explore_outlined,
        title: 'Page not found',
        message: 'Return to your workspace to continue.',
        action: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Go to workspace'),
        ),
      ),
    ),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _WorkspaceShell extends ConsumerWidget {
  const _WorkspaceShell({required this.path, required this.child});
  final String path;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final admin =
        ref.watch(profileProvider).asData?.value?.role == UserRole.admin;
    final routes = admin
        ? ['/', '/expenses', '/day-end', '/more']
        : ['/', '/expenses', '/more'];
    final index = path == '/'
        ? 0
        : path == '/expenses'
        ? 1
        : admin && path == '/day-end'
        ? 2
        : routes.length - 1;
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (index) => context.go(routes[index]),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view_rounded),
            label: admin ? 'Overview' : 'My day',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Expenses',
          ),
          if (admin)
            const NavigationDestination(
              icon: Icon(Icons.fact_check_outlined),
              selectedIcon: Icon(Icons.fact_check),
              label: 'Day end',
            ),
          const NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

CustomTransitionPage<void> _page(GoRouterState state, Widget child) =>
    CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          pageMotion(context, animation, child),
    );

class _AccessScreen extends ConsumerWidget {
  const _AccessScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: StatusPanel(
      icon: Icons.person_outline,
      title: 'Let’s check your access',
      message: 'We couldn’t open your cafe account. Check your connection, or ask your administrator to activate your account.',
      action: Column(
        children: [
          FilledButton(
            onPressed: () {
              ref.invalidate(authUserProvider);
              ref.invalidate(profileProvider);
            },
            child: const Text('Try again'),
          ),
          const SizedBox(height: 12),
          TextButton(
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
            child: const Text('Sign out'),
          ),
        ],
      ),
    ),
  );
}
