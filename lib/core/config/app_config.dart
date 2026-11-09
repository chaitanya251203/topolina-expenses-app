import 'dart:convert';

class AppConfig {
  const AppConfig({required this.url, required this.publishableKey});
  const AppConfig.fromEnvironment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      publishableKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final String url, publishableKey;

  String? get validationError {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return 'This installation needs its cafe connection configured.';
    }
    if (publishableKey.startsWith('sb_publishable_') &&
        publishableKey.length > 25) {
      return null;
    }
    try {
      final parts = publishableKey.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ) as Map<String, dynamic>;
        if (payload['role'] == 'anon') return null;
      }
    } catch (_) {
      /* Malformed or privileged credentials are not client keys. */
    }
    return 'This installation needs a valid public cafe connection key.';
  }
}
