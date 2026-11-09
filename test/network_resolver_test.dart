import 'dart:io';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/core/network/supabase_http_client.dart';

void main() {
  const host = 'cafe.supabase.co';
  test('healthy system DNS is used without public DNS requests', () async {
    var fallbacks = 0;
    final resolver = SupabaseHostResolver(
      host: host,
      systemLookup: (_) async => [InternetAddress('104.18.38.10')],
      fallbackLookup: (_) async {
        fallbacks++;
        return [InternetAddress('172.64.149.246')];
      },
    );
    expect((await resolver.lookup(host)).single.address, '104.18.38.10');
    expect(fallbacks, 0);
  });
  test(
    'failed system DNS falls back only for configured Supabase host',
    () async {
      var fallbacks = 0;
      final resolver = SupabaseHostResolver(
        host: host,
        systemLookup: (_) async =>
            throw const SocketException('Failed host lookup'),
        fallbackLookup: (_) async {
          fallbacks++;
          return [InternetAddress('104.18.38.10')];
        },
      );
      expect((await resolver.lookup(host)).single.address, '104.18.38.10');
      await expectLater(
        resolver.lookup('another.example'),
        throwsA(isA<SocketException>()),
      );
      expect(fallbacks, 1);
    },
  );
  test('simultaneous requests share lookup and cache expires', () async {
    var lookups = 0;
    var now = DateTime.utc(2026, 11, 9);
    final resolver = SupabaseHostResolver(
      host: host,
      clock: () => now,
      systemLookup: (_) async {
        lookups++;
        return [InternetAddress('104.18.38.10')];
      },
    );
    await Future.wait([resolver.lookup(host), resolver.lookup(host)]);
    await resolver.lookup(host);
    expect(lookups, 1);
    now = now.add(const Duration(seconds: 61));
    await resolver.lookup(host);
    expect(lookups, 2);
  });
  test(
    'unavailable DNS still fails clearly rather than fabricating a connection',
    () async {
      final resolver = SupabaseHostResolver(
        host: host,
        systemLookup: (_) async => [],
        fallbackLookup: (_) async => [],
      );
      await expectLater(resolver.lookup(host), throwsA(isA<SocketException>()));
    },
  );

  for (final configuredOrigin in [true, false]) {
    test(
      'HTTPS ${configuredOrigin ? 'project' : 'other'} connection performs TLS before any HTTP data',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final firstByte = Completer<int>();
        final subscription = server.listen((socket) {
          socket.listen((bytes) {
            if (bytes.isNotEmpty && !firstByte.isCompleted) {
              firstByte.complete(bytes.first);
            }
            socket.destroy();
          }, onError: (Object _) => socket.destroy());
        });
        final target = Uri.https(
          'localhost:${server.port}',
          '/auth/v1/settings',
        );
        final client = createSupabaseHttpClient(
          configuredOrigin ? target : Uri.https(host),
        );
        try {
          final request = client.get(
            target,
            headers: {'apikey': 'test-public-key'},
          );
          final rejected = expectLater(request, throwsException);
          // 0x16 is a TLS handshake record. A raw socket regression would send
          // an ASCII HTTP method (e.g. 0x47 for GET), exposing headers immediately.
          expect(
            await firstByte.future.timeout(const Duration(seconds: 5)),
            0x16,
          );
          await rejected;
        } finally {
          client.close();
          await subscription.cancel();
          await server.close();
        }
      },
    );
  }
}
