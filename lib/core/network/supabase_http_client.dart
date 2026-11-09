import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

typedef HostLookup = Future<List<InternetAddress>> Function(String host);

/// Resolves only the configured Supabase host through public encrypted DNS when
/// the device's resolver fails. Financial HTTP requests still go directly to
/// Supabase; their original HTTPS hostname/certificate verification is retained.
class SupabaseHostResolver {
  SupabaseHostResolver({
    required this.host,
    HostLookup? systemLookup,
    HostLookup? fallbackLookup,
    DateTime Function()? clock,
  }) : _systemLookup = systemLookup ?? InternetAddress.lookup,
       _fallbackLookup = fallbackLookup ?? _encryptedLookup,
       _clock = clock ?? DateTime.now;

  final String host;
  final HostLookup _systemLookup, _fallbackLookup;
  final DateTime Function() _clock;
  List<InternetAddress>? _cached;
  DateTime? _expires;
  Future<List<InternetAddress>>? _pending;

  Future<List<InternetAddress>> lookup(String requestedHost) async {
    if (requestedHost != host) return _systemLookup(requestedHost);
    if (_cached != null && _expires!.isAfter(_clock())) return _cached!;
    return _pending ??= _lookup().whenComplete(() => _pending = null);
  }

  Future<List<InternetAddress>> _lookup() async {
    List<InternetAddress> addresses;
    try {
      addresses = await _systemLookup(host).timeout(const Duration(seconds: 4));
      if (addresses.isEmpty) throw const SocketException('No DNS answer');
    } on SocketException {
      addresses = await _fallbackLookup(host)
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      addresses = await _fallbackLookup(host)
          .timeout(const Duration(seconds: 6));
    }
    if (addresses.isEmpty) {
      throw const SocketException('Unable to resolve cafe connection');
    }
    _cached = addresses;
    _expires = _clock().add(const Duration(seconds: 60));
    return addresses;
  }

  static Future<List<InternetAddress>> _encryptedLookup(String host) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client
          .getUrl(
            Uri.https('dns.google', '/resolve', {
              'name': host,
              'type': 'A',
              'edns_client_subnet': '0.0.0.0/0',
            }),
          )
          .timeout(const Duration(seconds: 5));
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw const SocketException('DNS service unavailable');
      }
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 5));
      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['Status'] != 0) throw const SocketException('No DNS answer');
      final result = <InternetAddress>[];
      for (final row in (json['Answer'] as List? ?? const [])) {
        if (row is! Map || row['type'] != 1 || row['data'] is! String) continue;
        final address = InternetAddress.tryParse(row['data'] as String);
        if (address != null &&
            address.type == InternetAddressType.IPv4 &&
            !address.isLoopback &&
            !address.isLinkLocal &&
            !address.isMulticast) {
          result.add(address);
        }
      }
      if (result.isEmpty) throw const SocketException('No DNS answer');
      return result;
    } finally {
      client.close(force: true);
    }
  }
}

http.Client createSupabaseHttpClient(Uri projectUrl) {
  final resolver = SupabaseHostResolver(host: projectUrl.host);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort!);
    if (uri.host != projectUrl.host ||
        uri.scheme != 'https' ||
        uri.port != projectUrl.port) {
      return uri.scheme == 'https'
          ? SecureSocket.startConnect(uri.host, uri.port)
          : Socket.startConnect(uri.host, uri.port);
    }
    final addresses = await resolver.lookup(uri.host);
    // IPv4 works on the affected cafe network and avoids IPv6-only routing.
    final address = addresses.firstWhere(
      (a) => a.type == InternetAddressType.IPv4,
      orElse: () => addresses.first,
    );
    return _secureConnection(address, uri.port, uri.host);
  };
  // No badCertificateCallback: Dart checks TLS against the original request URL.
  return IOClient(client);
}

/// A custom HttpClient connectionFactory owns TLS as well as the TCP socket.
/// Always authenticate the original hostname, never the resolved IP address.
Future<ConnectionTask<Socket>> _secureConnection(
  InternetAddress address,
  int port,
  String originalHost,
) async {
  final tcp = await Socket.startConnect(address, port);
  final result = Completer<Socket>();
  Socket? connected;
  SecureSocket? secure;
  var cancelled = false;
  unawaited(
    tcp.socket.then(
      (socket) async {
        connected = socket;
        if (cancelled) {
          socket.destroy();
          return;
        }
        try {
          secure = await SecureSocket.secure(socket, host: originalHost);
          if (cancelled) {
            secure!.destroy();
            return;
          }
          result.complete(secure);
        } catch (error, stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    ),
  );
  return ConnectionTask.fromSocket(result.future, () {
    cancelled = true;
    tcp.cancel();
    connected?.destroy();
    secure?.destroy();
    if (!result.isCompleted) {
      result.completeError(const SocketException('Connection cancelled'));
    }
  });
}
