import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../authentication/auth_repository.dart';

class ExpenseCategory {
  const ExpenseCategory({
    required this.id,
    required this.name,
    required this.active,
    this.iconKey,
  });
  final String id, name;
  final bool active;
  final String? iconKey;
}

abstract interface class CategoryRepository {
  Future<List<ExpenseCategory>> list();
}

class SupabaseCategoryRepository implements CategoryRepository {
  SupabaseCategoryRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<ExpenseCategory>> list() async {
    final data = await client
        .from('categories')
        .select('id,name,active,icon_key')
        .order('name');
    return data
        .map(
          (row) => ExpenseCategory(
            id: row['id'] as String,
            name: row['name'] as String,
            active: row['active'] as bool,
            iconKey: row['icon_key'] as String?,
          ),
        )
        .toList();
  }
}

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => SupabaseCategoryRepository(Supabase.instance.client),
);
final categoriesProvider = FutureProvider<List<ExpenseCategory>>((ref) async {
  ref.watch(authUserProvider);
  return ref.watch(categoryRepositoryProvider).list();
});
