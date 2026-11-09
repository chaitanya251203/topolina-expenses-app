import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/status_panel.dart';
import 'router.dart';
import 'theme.dart';

class TopolinaApp extends ConsumerWidget {
  const TopolinaApp({super.key, this.startupError});
  final String? startupError;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (startupError != null) {
      return MaterialApp(
        title: 'Topolina',
        debugShowCheckedModeBanner: false,
        theme: TopolinaTheme.light,
        home: Scaffold(
          body: StatusPanel(
            icon: Icons.settings_outlined,
            title: 'Let’s get connected',
            message: startupError!,
          ),
        ),
      );
    }
    return MaterialApp.router(
      title: 'Topolina',
      debugShowCheckedModeBanner: false,
      theme: TopolinaTheme.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
