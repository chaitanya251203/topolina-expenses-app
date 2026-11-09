import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/core/config/app_config.dart';

void main() {
  test('accept public keys only and reject insecure or malformed URLs', () {
    const url = 'https://example.supabase.co';
    expect(
      const AppConfig(
        url: url,
        publishableKey: 'sb_publishable_1234567890123456',
      ).validationError,
      isNull,
    );
    for (final bad in [
      'http://example.com',
      '',
      'https://user:pass@example.com',
      'https://example.com/path',
    ]) {
      expect(
        AppConfig(
          url: bad,
          publishableKey: 'sb_publishable_1234567890123456',
        ).validationError,
        isNotNull,
      );
    }
    String jwt(String role) =>
        'header.${base64Url.encode(utf8.encode(jsonEncode({'role': role})))}.signature';
    expect(
      AppConfig(url: url, publishableKey: jwt('anon')).validationError,
      isNull,
    );
    expect(
      AppConfig(url: url, publishableKey: jwt('service_role')).validationError,
      isNotNull,
    );
    expect(
      const AppConfig(
        url: url,
        publishableKey: 'sb_secret_invalid',
      ).validationError,
      isNotNull,
    );
  });
}
