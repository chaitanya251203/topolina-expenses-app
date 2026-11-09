import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../authentication/auth_repository.dart';

enum MasterKind { categories, vendors, items }

class MasterRecord {
  const MasterRecord(this.data);
  final Map<String, dynamic> data;
  String get id => data['id'] as String;
  String get name => data['name'] as String;
  bool get active => data['active'] as bool;
}

class MasterData {
  const MasterData(this.records);
  final Map<MasterKind, List<MasterRecord>> records;
  List<MasterRecord> forKind(MasterKind kind) => records[kind] ?? const [];
}

abstract interface class MasterRepository {
  Future<MasterData> load();
  Future<void> save(MasterKind kind, Map<String, dynamic> values, {String? id});
}

class SupabaseMasterRepository implements MasterRepository {
  SupabaseMasterRepository(this.client);
  final SupabaseClient client;
  @override
  Future<MasterData> load() async {
    final rows = await Future.wait(
      MasterKind.values.map(
        (kind) => client.from(kind.name).select().order('name'),
      ),
    );
    return MasterData({
      for (var i = 0; i < MasterKind.values.length; i++)
        MasterKind.values[i]: rows[i].map((row) => MasterRecord(row)).toList(),
    });
  }

  @override
  Future<void> save(
    MasterKind kind,
    Map<String, dynamic> values, {
    String? id,
  }) async {
    if (id == null) {
      await client.from(kind.name).insert(values).select('id').single();
    } else {
      await client
          .from(kind.name)
          .update(values)
          .eq('id', id)
          .select('id')
          .single();
    }
  }
}

final masterRepositoryProvider = Provider<MasterRepository>(
  (ref) => SupabaseMasterRepository(Supabase.instance.client),
);
final masterDataProvider = FutureProvider<MasterData>((ref) async {
  ref.watch(authUserProvider);
  final profile = await ref.watch(profileProvider.future);
  if (profile?.role != UserRole.admin || profile?.active != true) {
    throw StateError('Administrator access required.');
  }
  return ref.watch(masterRepositoryProvider).load();
});
