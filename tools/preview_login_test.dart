// Explicit visual-QA tool: flutter test tools/preview_login_test.dart.
// Uses the installed Flutter SDK fonts, and writes an ignored preview artifact.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/app/app.dart';
import 'package:topolina/features/authentication/auth_repository.dart';
import 'package:topolina/features/authentication/login_screen.dart';

import '../test/auth_flow_test.dart' show FakeAuth;

void main() {
  testWidgets('capture branded login for visual inspection', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.runAsync(() async {
      final font = await File(
        '.tooling/flutter/bin/cache/artifacts/material_fonts/roboto-regular.ttf',
      ).readAsBytes();
      await (FontLoader(
        'Roboto',
      )..addFont(Future.value(ByteData.sublistView(font)))).load();
      final icons = await File(
        '.tooling/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
      ).readAsBytes();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    });
    final auth = FakeAuth();
    addTearDown(auth.changes.close);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(auth)],
          child: const TopolinaApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/brand/topolina-logo.png'),
        tester.element(find.byType(LoginScreen)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final picture = await boundary.toImage(pixelRatio: 2);
      final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/previews/login.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      picture.dispose();
    });
  });
}
