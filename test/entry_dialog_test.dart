import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/app/theme.dart';
import 'package:topolina/core/widgets/entry_dialog.dart';
import 'package:topolina/features/expenses/expense_repository.dart';

void main() {
  testWidgets(
    'entry form retains values on failure and preserves password spaces',
    (tester) async {
      final saved = <Map<String, String>>[];
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: TopolinaTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  result = await showEntryForm(
                    context,
                    title: 'Create account',
                    fields: const [
                      EntryField('name', 'Name'),
                      EntryField(
                        'password',
                        'Password',
                        kind: EntryKind.password,
                      ),
                    ],
                    save: (v) async {
                      saved.add(v);
                      if (saved.length == 1) {
                        throw const ExpenseValidationException('Try again.');
                      }
                    },
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        '  Rahul  ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        ' a password ',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Try again.'), findsOneWidget);
      expect(find.text('  Rahul  '), findsOneWidget);
      expect(saved.single, {'name': 'Rahul', 'password': ' a password '});
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(result, true);
      expect(saved.length, 2);
    },
  );
  testWidgets(
    'entry form prevents duplicate submission while save is pending',
    (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showEntryForm(
                  context,
                  title: 'Save entry',
                  fields: const [
                    EntryField('reason', 'Reason', value: 'Correction'),
                  ],
                  save: (v) {
                    calls++;
                    return pending.future;
                  },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(calls, 1);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton).last).onPressed,
        isNull,
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
    },
  );
}
