import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';
import 'core/network/supabase_http_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig.fromEnvironment();
  String? error = config.validationError;
  if (error == null) {
    try {
      await Supabase.initialize(
        url: config.url,
        publishableKey: config.publishableKey,
        httpClient: createSupabaseHttpClient(Uri.parse(config.url)),
      );
    } catch (_) {
      error = 'Topolina could not start. Please reopen the app.';
    }
  }
  runApp(ProviderScope(child: TopolinaApp(startupError: error)));
}
