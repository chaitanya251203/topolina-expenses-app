import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../staff/staff_repository.dart';
import '../expenses/expense_repository.dart';

const backupMaxBytes = 60 * 1024 * 1024;

class BackupCodec {
  static JsonRow validate(JsonRow data) {
    if (data['format'] != 'topolina-backup' ||
        data['version'] != 1 ||
        data['project_id'] is! String ||
        data['payload'] is! String ||
        data['sha256'] is! String) {
      throw const FormatException('This is not a supported Topolina backup.');
    }
    final bytes = utf8.encode(data['payload'] as String);
    if (bytes.length > 50 * 1024 * 1024) {
      throw const FormatException(
        'This backup exceeds the mobile restore limit of 50 MB.',
      );
    }
    if (sha256.convert(bytes).toString() != data['sha256']) {
      throw const FormatException(
        'The backup checksum does not match. The file may be damaged.',
      );
    }
    return data;
  }

  static JsonRow decode(Uint8List bytes) {
    if (bytes.length > backupMaxBytes) {
      throw const FormatException('The backup file is too large.');
    }
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map) throw const FormatException('Invalid backup file.');
      return validate(JsonRow.from(decoded));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Unable to read this backup file.');
    }
  }

  static Uint8List encode(JsonRow data) =>
      Uint8List.fromList(utf8.encode(jsonEncode(validate(data))));
}

class BackupRepository {
  BackupRepository(this.client);
  final SupabaseClient client;
  Future<JsonRow> status() async {
    final results = await Future.wait([
      client.rpc('backup_status'),
      client.rpc('backup_scheduler_status'),
    ]);
    return {...JsonRow.from(results[0] as Map), 'scheduler_ready': results[1]};
  }

  Future<String> create() async =>
      (await client.rpc('create_backup')) as String;
  Future<JsonRow> download(String id) async => BackupCodec.validate(
    JsonRow.from(
      await client.rpc('download_backup', params: {'p_id': id}) as Map,
    ),
  );
  Future<void> configure(bool enabled, int interval, int count) async {
    await client.rpc(
      'configure_backups',
      params: {
        'p_enabled': enabled,
        'p_interval_hours': interval,
        'p_retention': count,
      },
    );
  }

  Future<void> restore(JsonRow backup, String reason, String password) async {
    final email = client.auth.currentUser?.email;
    if (email == null) {
      throw const ExpenseValidationException(
        'Sign in again to restore a backup.',
      );
    }
    try {
      await client.auth.signInWithPassword(email: email, password: password);
    } on AuthException {
      throw const ExpenseValidationException(
        'The current password could not be verified.',
      );
    }
    await client.rpc(
      'restore_backup',
      params: {'p_backup': BackupCodec.validate(backup), 'p_reason': reason},
    );
  }
}

final backupRepositoryProvider = Provider(
  (ref) => BackupRepository(Supabase.instance.client),
);
