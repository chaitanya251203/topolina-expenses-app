import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:topolina/app/theme.dart';
import 'package:topolina/features/authentication/auth_repository.dart';
import 'package:topolina/features/reconciliation/day_end_screen.dart';
import 'package:topolina/features/reconciliation/finance_repository.dart';
import 'package:topolina/features/sales/sales_screen.dart';

DaySummary summary({
  String date = '2026-11-09',
  String state = 'open',
  bool hasSales = true,
  int expected = 1000000,
  int cash = 500000,
  int online = 350000,
  int other = 50000,
  int paid = 100000,
  int incurred = 150000,
  int outstanding = 50000,
  String? notes,
  List<DayPayment> payments = const [],
}) => DaySummary(
  businessDate: date,
  state: state,
  hasSales: hasSales,
  expectedPaise: hasSales ? expected : null,
  cashPaise: cash,
  onlinePaise: online,
  otherPaise: other,
  paidPaise: paid,
  incurredPaise: incurred,
  outstandingPaise: outstanding,
  differencePaise: hasSales ? expected - cash - online - other - paid : null,
  notes: notes,
  payments: payments,
);

class FakeFinanceRepository implements FinanceRepository {
  FakeFinanceRepository({DaySummary? initial}) : value = initial ?? summary();
  DaySummary value;
  int contextCalls = 0, dayCalls = 0, closeCalls = 0, reopenCalls = 0;
  String? closingReason, reopeningReason;
  final saved = <SalesDraft>[];
  Object? saveError, closeError, reopenError;
  Completer<void>? pendingSave;
  @override
  Future<FinancialEntryContext> entryContext() async {
    contextCalls++;
    return FinancialEntryContext(
      serverTime: DateTime.parse('2026-11-09T09:00:00Z'),
      businessDates: const ['2026-11-09'],
    );
  }

  @override
  Future<DaySummary> day(String date) async {
    dayCalls++;
    return value;
  }

  @override
  Future<void> saveSales(SalesDraft draft) async {
    saved.add(draft);
    if (pendingSave != null) await pendingSave!.future;
    if (saveError != null) throw saveError!;
    value = summary(
      date: draft.businessDate,
      expected: draft.expectedPaise,
      cash: draft.cashPaise,
      online: draft.onlinePaise,
      other: draft.otherPaise,
      paid: value.paidPaise,
      notes: draft.notes,
    );
  }

  @override
  Future<void> closeDay(String date, String? reason) async {
    closeCalls++;
    closingReason = reason;
    if (closeError != null) throw closeError!;
    value = summary(
      date: date,
      state: 'closed',
      expected: value.expectedPaise!,
      cash: value.cashPaise,
      online: value.onlinePaise,
      other: value.otherPaise,
      paid: value.paidPaise,
    );
  }

  @override
  Future<void> reopenDay(String date, String reason) async {
    reopenCalls++;
    reopeningReason = reason;
    if (reopenError != null) throw reopenError!;
    value = summary(
      date: date,
      state: 'reopened',
      expected: value.expectedPaise ?? 0,
      cash: value.cashPaise,
      online: value.onlinePaise,
      other: value.otherPaise,
      paid: value.paidPaise,
    );
  }
}

void main() {
  Future<void> open(
    WidgetTester tester,
    FinanceRepository repository,
    Widget screen, {
    UserRole role = UserRole.admin,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          financeRepositoryProvider.overrideWithValue(repository),
          profileProvider.overrideWith(
            (ref) async => SessionProfile(
              id: 'user',
              name: 'Cafe Admin',
              role: role,
              active: true,
              serverTime: DateTime.parse('2026-11-09T09:00:00Z'),
            ),
          ),
        ],
        child: MaterialApp(theme: TopolinaTheme.light, home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> visible(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        220,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 30,
      );
    }
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  Future<void> enter(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(ValueKey(key));
    await visible(tester, finder);
    await tester.enterText(finder, value);
    await tester.pump();
  }

  test('day models preserve exact amounts and distinguish balanced, short and excess', () {
    expect(summary().balanceLabel, 'Balanced');
    expect(summary(expected: 1000001).balanceLabel, 'Short');
    expect(summary(expected: 999999).balanceLabel, 'Excess');
    expect(summary().accountedPaise, 1000000);
    final parsed = DaySummary.fromJson({
      'business_date': '2026-11-09',
      'state': 'open',
      'has_sales': true,
      'expected_paise': 10050,
      'cash_paise': 10000,
      'online_paise': 0,
      'other_paise': 0,
      'paid_paise': 50,
      'incurred_paise': 2000,
      'outstanding_paise': 1950,
      'difference_paise': 0,
      'notes': 'Keep notes',
      'payments': [],
    });
    expect(parsed.expectedPaise, 10050);
    expect(parsed.accountedPaise, 10050);
    expect(parsed.notes, 'Keep notes');
  });

  testWidgets('sales save exact paise and retain user edits across rebuilds', (
    tester,
  ) async {
    final repo = FakeFinanceRepository(
      initial: summary(hasSales: false, cash: 0, online: 0, other: 0),
    );
    await open(tester, repo, const SalesScreen());
    await enter(tester, 'sales-expected', '10000.55');
    await enter(tester, 'sales-cash', '5000.25');
    await enter(tester, 'sales-online', '4000.30');
    await enter(tester, 'sales-other', '500');
    await enter(tester, 'sales-notes', '  Reviewed totals  ');
    await visible(tester, find.text('Save sales'));
    await tester.tap(find.text('Save sales'));
    await tester.pumpAndSettle();
    expect(repo.saved, hasLength(1));
    final saved = repo.saved.single;
    expect(saved.expectedPaise, 1000055);
    expect(saved.cashPaise, 500025);
    expect(saved.onlinePaise, 400030);
    expect(saved.otherPaise, 50000);
    expect(saved.notes, 'Reviewed totals');
    await visible(tester, find.text('Sales saved.'));
    expect(find.text('Sales saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sales validation and duplicate tap guard prevent invalid or repeated saves',
    (tester) async {
      final repo = FakeFinanceRepository(
        initial: summary(hasSales: false, cash: 0, online: 0, other: 0),
      );
      await open(tester, repo, const SalesScreen());
      await enter(tester, 'sales-expected', '100.001');
      await visible(tester, find.text('Save sales'));
      await tester.tap(find.text('Save sales'));
      await tester.pumpAndSettle();
      expect(repo.saved, isEmpty);
      await enter(tester, 'sales-expected', '100.50');
      repo.pendingSave = Completer<void>();
      await visible(tester, find.text('Save sales'));
      await tester.tap(find.text('Save sales'));
      await tester.pump();
      final button = find.byType(FilledButton).last;
      await tester.tap(button);
      await tester.pump();
      expect(repo.saved, hasLength(1));
      repo.pendingSave!.complete();
      await tester.pumpAndSettle();
      expect(repo.saved, hasLength(1));
    },
  );

  testWidgets(
    'a failed sales save keeps the entered values and reports no success',
    (tester) async {
      final repo = FakeFinanceRepository()
        ..saveError = const PostgrestException(
          message: 'This day is closed.',
          code: 'P0001',
        );
      await open(tester, repo, const SalesScreen());
      await enter(tester, 'sales-expected', '12345.67');
      final controller = tester
          .widget<TextFormField>(find.byKey(const ValueKey('sales-expected')))
          .controller!;
      await visible(tester, find.text('Save sales'));
      await tester.tap(find.text('Save sales'));
      await tester.pumpAndSettle();
      await visible(tester, find.text('This day is closed.'));
      expect(find.text('Sales saved.'), findsNothing);
      expect(controller.text, '12345.67');
    },
  );

  testWidgets(
    'day-end shows a real payment contributor and excludes unpaid amounts',
    (tester) async {
      final repo = FakeFinanceRepository(
        initial: summary(
          payments: const [
            DayPayment(
              id: 'p',
              expenseId: 'e',
              description: 'Milk purchase',
              categoryName: 'Dairy',
              amountPaise: 100000,
              mode: 'cash',
              createdByName: 'Rahul',
            ),
          ],
        ),
      );
      await open(tester, repo, const DayEndScreen());
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('balance-status'))).data,
        'Balanced',
      );
      await visible(tester, find.text('Milk purchase'));
      expect(find.text('Dairy · Rahul'), findsOneWidget);
      expect(find.text('Cash payment'), findsOneWidget);
      await visible(tester, find.text('Expenses paid this day'));
      expect(repo.value.paidPaise, 100000);
      expect(repo.value.incurredPaise, 150000);
      expect(repo.value.accountedPaise, 1000000);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('no sales means the day cannot be closed', (tester) async {
    final repo = FakeFinanceRepository(initial: summary(hasSales: false));
    await open(tester, repo, const DayEndScreen());
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('balance-status'))).data,
      'Sales not recorded',
    );
    await visible(tester, find.text('Close business day'));
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Close business day'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(repo.closeCalls, 0);
  });

  testWidgets(
    'short day requires a reason before close and refreshes the closed state',
    (tester) async {
      final repo = FakeFinanceRepository(initial: summary(expected: 1000100));
      await open(tester, repo, const DayEndScreen());
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('balance-status'))).data,
        'Short',
      );
      await visible(tester, find.text('Close business day'));
      await tester.tap(find.text('Close business day'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm close'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a reason to continue.'), findsOneWidget);
      expect(repo.closeCalls, 0);
      await tester.enterText(
        find.byKey(const ValueKey('day-action-reason')),
        '  Cash short by ₹1  ',
      );
      await tester.tap(find.text('Confirm close'));
      await tester.pumpAndSettle();
      expect(repo.closeCalls, 1);
      expect(repo.closingReason, 'Cash short by ₹1');
      expect(repo.value.isClosed, isTrue);
      await visible(tester, find.text('Business day closed.'));
      expect(find.text('Business day closed.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a failed close does not claim the day is closed', (
    tester,
  ) async {
    final repo = FakeFinanceRepository()
      ..closeError = const PostgrestException(
        message: 'The day changed. Review it again.',
        code: 'P0001',
      );
    await open(tester, repo, const DayEndScreen());
    await visible(tester, find.text('Close business day'));
    await tester.tap(find.text('Close business day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm close'));
    await tester.pumpAndSettle();
    expect(repo.value.isClosed, isFalse);
    expect(find.text('Business day closed.'), findsNothing);
    await visible(tester, find.text('The day changed. Review it again.'));
  });

  testWidgets('historical closed day requires a reason before reopening', (
    tester,
  ) async {
    final repo = FakeFinanceRepository(
      initial: summary(date: '2026-11-08', state: 'closed'),
    );
    await open(tester, repo, const DayEndScreen(initialDate: '2026-11-08'));
    await visible(tester, find.text('Reopen day'));
    await tester.tap(find.text('Reopen day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm reopen'));
    await tester.pumpAndSettle();
    expect(repo.reopenCalls, 0);
    expect(find.text('Enter a reason to continue.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('day-action-reason')),
      'Correct collection entry',
    );
    await tester.tap(find.text('Confirm reopen'));
    await tester.pumpAndSettle();
    expect(repo.reopenCalls, 1);
    expect(repo.reopeningReason, 'Correct collection entry');
    expect(repo.value.state, 'reopened');
    expect(repo.value.canEdit(await repo.entryContext()), isTrue);
  });

  testWidgets('waiter cannot load sales or reconciliation data', (
    tester,
  ) async {
    final repo = FakeFinanceRepository();
    await open(tester, repo, const SalesScreen(), role: UserRole.waiter);
    expect(find.text('Administrator access'), findsOneWidget);
    expect(repo.contextCalls, 0);
    await open(tester, repo, const DayEndScreen(), role: UserRole.waiter);
    expect(find.text('Administrator access'), findsOneWidget);
    expect(repo.dayCalls, 0);
  });

  testWidgets('large text keeps the day-end screen and reason dialog usable', (
    tester,
  ) async {
    final repo = FakeFinanceRepository(initial: summary(expected: 1000100));
    await open(tester, repo, const DayEndScreen(), textScale: 1.8);
    await visible(tester, find.text('Close business day'));
    await tester.tap(find.text('Close business day'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm close'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
