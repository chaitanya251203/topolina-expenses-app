import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum UserRole { admin, waiter }

class SessionProfile {
  const SessionProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.active,
    required this.serverTime,
    this.permissions = const ['expenses.create', 'expenses.read_own'],
  });
  final String id, name;
  final UserRole role;
  final bool active;
  final DateTime serverTime;
  final List<String> permissions;
  bool can(String permission) =>
      role == UserRole.admin || permissions.contains(permission);
  factory SessionProfile.fromJson(Map<String, dynamic> json) => SessionProfile(
    id: json['id'] as String,
    name: json['full_name'] as String,
    role: UserRole.values.byName(json['role_code'] as String),
    active: json['active'] as bool,
    serverTime: DateTime.parse(json['server_time'] as String),
    permissions:
        (json['permissions'] as List? ??
                ['expenses.create', 'expenses.read_own'])
            .cast<String>(),
  );
}

abstract interface class AuthRepository {
  Stream<String?> watchUserId();
  Future<SessionProfile> loadProfile();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client);
  final SupabaseClient client;
  @override
  Stream<String?> watchUserId() async* {
    yield client.auth.currentUser?.id;
    yield* client.auth.onAuthStateChange.map((event) => event.session?.user.id);
  }

  @override
  Future<SessionProfile> loadProfile() async => SessionProfile.fromJson(
    Map<String, dynamic>.from(await client.rpc('session_context') as Map),
  );
  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  }

  @override
  Future<void> signOut() => client.auth.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client),
);
final authUserProvider = StreamProvider<String?>(
  (ref) => ref.watch(authRepositoryProvider).watchUserId(),
);
final profileProvider = FutureProvider<SessionProfile?>((ref) async {
  final user = ref.watch(authUserProvider);
  if (user.asData?.value == null) return null;
  return ref.watch(authRepositoryProvider).loadProfile();
});
