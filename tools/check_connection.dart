import 'dart:convert';
import 'dart:io';

import 'package:topolina/core/network/supabase_http_client.dart';

Future<void> main(List<String> arguments) async {
  final config = jsonDecode(
    await File('config/supabase.local.json').readAsString(),
  ) as Map<String, dynamic>;
  final project = Uri.parse(config['SUPABASE_URL'] as String);
  if (arguments.contains('--diagnose')) {
    try {
      final answers = await InternetAddress.lookup(project.host);
      stdout.writeln('System DNS: ${answers.length} answer(s).');
    } on SocketException {
      stdout.writeln('System DNS: failed host lookup.');
    }
    await Future.wait(
      [
        Uri.parse(
          'https://cloudflare-dns.com/dns-query?name=${project.host}&type=A',
        ),
        Uri.parse('https://dns.google/resolve?name=${project.host}&type=A'),
        Uri.parse('https://www.google.com/'),
      ].map((uri) async {
        final diagnostic = HttpClient()
          ..connectionTimeout = const Duration(seconds: 5);
        try {
          final request = await diagnostic
              .getUrl(uri)
              .timeout(const Duration(seconds: 8));
          request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
          final response = await request.close().timeout(
            const Duration(seconds: 8),
          );
          stdout.writeln('Strict HTTPS ${uri.host}: ${response.statusCode}.');
          await response.drain<void>();
        } on HandshakeException {
          stdout.writeln(
            'Strict HTTPS ${uri.host}: certificate validation failed.',
          );
        } catch (error) {
          stdout.writeln('Strict HTTPS ${uri.host}: ${error.runtimeType}.');
        } finally {
          diagnostic.close(force: true);
        }
      }),
    );
  }
  final client = createSupabaseHttpClient(project);
  try {
    final response = await client
        .get(
          project.resolve('/auth/v1/settings'),
          headers: {'apikey': config['SUPABASE_PUBLISHABLE_KEY'] as String},
        )
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      if (arguments.contains('--diagnose')) {
        stdout.writeln(
          'Read-only endpoint response: ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}',
        );
      }
      throw HttpException('Connection check failed: ${response.statusCode}');
    }
    stdout.writeln(
      'Verified HTTPS connection to Supabase using the app transport.',
    );
    final email = Platform.environment['TOPOLINA_SMOKE_EMAIL'];
    final password = Platform.environment['TOPOLINA_SMOKE_PASSWORD'];
    if (email != null && password != null) {
      final login = await client
          .post(
            project.resolve('/auth/v1/token?grant_type=password'),
            headers: {
              'apikey': config['SUPABASE_PUBLISHABLE_KEY'] as String,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 25));
      if (login.statusCode != 200) {
        throw HttpException(
          'Authenticated connection check failed: ${login.statusCode}',
        );
      }
      final token =
          (jsonDecode(login.body) as Map<String, dynamic>)['access_token']
              as String;
      final headers = {
        'apikey': config['SUPABASE_PUBLISHABLE_KEY'] as String,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };
      try {
        final context = await client
            .post(
              project.resolve('/rest/v1/rpc/entry_context'),
              headers: headers,
              body: '{}',
            )
            .timeout(const Duration(seconds: 25));
        if (context.statusCode != 200) {
          throw HttpException(
            'Entry context check failed: ${context.statusCode}',
          );
        }
        final date =
            ((jsonDecode(context.body)
                            as Map<String, dynamic>)['business_dates']
                        as List)
                    .first
                as String;
        final dashboard = await client
            .post(
              project.resolve('/rest/v1/rpc/get_dashboard'),
              headers: headers,
              body: jsonEncode({'p_date': date}),
            )
            .timeout(const Duration(seconds: 25));
        if (dashboard.statusCode != 200) {
          throw HttpException(
            'Dashboard check failed: ${dashboard.statusCode}',
          );
        }
        final result = jsonDecode(dashboard.body) as Map<String, dynamic>;
        if (result['day'] is! Map) {
          throw const FormatException('Dashboard shape mismatch');
        }
        stdout.writeln(
          'Verified authenticated entry context and dashboard through the app transport.',
        );
      } finally {
        await client
            .post(
              project.resolve('/auth/v1/logout?scope=local'),
              headers: headers,
            )
            .timeout(const Duration(seconds: 10));
      }
    }
  } finally {
    client.close();
  }
}
