import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../authentication/auth_repository.dart';
import '../expenses/expense_repository.dart';

class DashboardSnapshot {
  const DashboardSnapshot(this.data);
  final Map<String, dynamic> data;
  Map<String, dynamic> get day => Map<String, dynamic>.from(data['day'] as Map);
  String get date => day['business_date'] as String;
  int total(String key) => (data[key] as int?) ?? 0;
}

abstract interface class DashboardRepository {
  Future<DashboardSnapshot> load();
}

class SupabaseDashboardRepository implements DashboardRepository {
  SupabaseDashboardRepository(this.client);
  final SupabaseClient client;
  @override
  Future<DashboardSnapshot> load() async {
    final context = Map<String, dynamic>.from(
      await client.rpc('entry_context') as Map,
    );
    final date = (context['business_dates'] as List).first as String;
    return DashboardSnapshot(
      Map<String, dynamic>.from(
        await client.rpc('get_dashboard', params: {'p_date': date}) as Map,
      ),
    );
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => SupabaseDashboardRepository(Supabase.instance.client),
);
final dashboardProvider = FutureProvider<DashboardSnapshot>((ref) async {
  ref.watch(authUserProvider);
  ref.watch(financialChangesProvider);
  return ref.watch(dashboardRepositoryProvider).load();
});
