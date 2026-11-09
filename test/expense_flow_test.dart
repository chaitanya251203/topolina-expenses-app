import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/app/theme.dart';
import 'package:topolina/features/authentication/auth_repository.dart';
import 'package:topolina/features/credit/credit_screen.dart';
import 'package:topolina/features/expenses/expense_form_screen.dart';
import 'package:topolina/features/expenses/expense_repository.dart';
import 'package:topolina/features/expenses/expenses_screen.dart';

final contextFixture = ExpenseEntryContext(
  serverTime: DateTime.parse('2026-11-08T19:00:00Z'),
  businessDates: const ['2026-11-09', '2026-11-08'],
  categories: const [
    ExpenseChoice(id: 'grocery', name: 'Grocery'),
    ExpenseChoice(id: 'salary', name: 'Salary'),
  ],
  items: const [],
  vendors: const [ExpenseChoice(id: 'supplier', name: 'ABC Suppliers')],
);

ExpenseRecord purchase({int paid = 100000}) => ExpenseRecord(
  id: 'purchase',
  date: '2026-11-08',
  categoryId: 'grocery',
  categoryName: 'Grocery',
  description: 'Groceries on credit',
  amountPaise: 200000,
  paidPaise: paid,
  outstandingPaise: 200000 - paid,
  status: paid == 200000 ? 'paid' : 'partially_paid',
  createdBy: 'admin',
  createdByName: 'Cafe Admin',
  vendorId: 'supplier',
  vendorName: 'ABC Suppliers',
  payments: const [],
);

class FakeExpenseRepository implements ExpenseRepository {
  final created = <ExpenseDraft>[], payments = <CreditPaymentDraft>[];
  final requestedDates = <String?>[];
  List<ExpenseRecord> records = [purchase()];
  Completer<void>? createWait;
  bool failCreate = false;
  int listCalls = 0;
  @override
  Future<ExpenseEntryContext> entryContext() async => contextFixture;
  @override
  Future<List<ExpenseRecord>> list({
    String? from,
    String? to,
    bool outstandingOnly = false,
  }) async {
    listCalls++;
    requestedDates.add(from);
    return records
        .where((r) => outstandingOnly ? r.outstandingPaise > 0 : r.date == from)
        .toList();
  }

  @override
  Future<void> create(ExpenseDraft draft) async {
    draft.validate();
    created.add(draft);
    if (failCreate) throw Exception('Connection interrupted');
    if (createWait != null) await createWait!.future;
  }

  @override
  Future<void> pay(CreditPaymentDraft draft) async {
    payments.add(draft);
    records = [purchase(paid: 100000 + draft.amountPaise)];
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    FakeExpenseRepository repository,
    Widget child, {
    UserRole role = UserRole.admin,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          expenseRepositoryProvider.overrideWithValue(repository),
          creditPaidMonthProvider.overrideWith((ref) async => 0),
          authUserProvider.overrideWith((ref) => Stream.value(role.name)),
          profileProvider.overrideWith(
            (ref) async => SessionProfile(
              id: role.name,
              name: 'Cafe Admin',
              role: role,
              active: true,
              serverTime: contextFixture.serverTime,
            ),
          ),
        ],
        child: MaterialApp(theme: TopolinaTheme.light, home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openForm(
    WidgetTester tester,
    FakeExpenseRepository repository, {
    UserRole role = UserRole.admin,
  }) async {
    await mount(
      tester,
      repository,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<bool>(
                  builder: (_) => const ExpenseFormScreen(),
                ),
              ),
              child: const Text('Open expense form'),
            ),
          ),
        ),
      ),
      role: role,
    );
    await tester.tap(find.text('Open expense form'));
    await tester.pumpAndSettle();
  }

  Future<void> fillBasics(WidgetTester tester) async {
    await tester.tap(find.text('Select category'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grocery'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('expense-description')),
      'Fresh vegetables',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('expense-amount')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('expense-amount')), '100.50');
  }

  Future<void> reachSave(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-expense')),
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  test('draft serialization preserves exact paise and excludes unpaid payment modes', () {
    const draft = ExpenseDraft(
      id: 'id',
      date: '2026-11-09',
      categoryId: 'salary',
      description: 'Expense',
      amountPaise: 10050,
      paidPaise: 0,
      paymentMode: 'cash',
    );
    draft.validate();
    expect(draft.toParams()['p_amount_paise'], 10050);
    expect(draft.toParams()['p_paid_paise'], 0);
    expect(draft.toParams()['p_payment_mode'], isNull);
    const excessive = ExpenseDraft(
      id: 'id',
      date: '2026-11-09',
      categoryId: 'grocery',
      description: 'Expense',
      amountPaise: 100,
      paidPaise: 101,
      paymentMode: 'cash',
    );
    expect(excessive.validate, throwsA(isA<ExpenseValidationException>()));
  });
  test(
    'calculated draft validates half-up rounding and quantity precision',
    () {
      const draft = ExpenseDraft(
        id: 'id',
        date: '2026-11-09',
        categoryId: 'grocery',
        description: 'Expense',
        amountPaise: 101,
        paidPaise: 0,
        quantity: '1.005',
        ratePaise: 100,
      );
      draft.validate();
      expect(draft.toParams()['p_quantity'], '1.005');
      const invalid = ExpenseDraft(
        id: 'id',
        date: '2026-11-09',
        categoryId: 'grocery',
        description: 'Expense',
        amountPaise: 100,
        paidPaise: 0,
        quantity: '1.0000001',
        ratePaise: 100,
      );
      expect(invalid.validate, throwsA(isA<ExpenseValidationException>()));
    },
  );
  test('request identity retries the same values and changes when the draft changes', () {
    final identity = ExpenseRequestIdentity();
    final first = identity.forValues({
      'amount': 10050,
      'description': 'Vegetables',
    });
    expect(
      identity.forValues({'amount': 10050, 'description': 'Vegetables'}),
      first,
    );
    expect(
      identity.forValues({'amount': 10051, 'description': 'Vegetables'}),
      isNot(first),
    );
  });
  testWidgets('paid expense submits exact paise once despite repeated taps', (
    tester,
  ) async {
    final repository = FakeExpenseRepository()..createWait = Completer<void>();
    await openForm(tester, repository);
    await fillBasics(tester);
    await reachSave(tester);
    await tester.tap(find.byKey(const Key('save-expense')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-expense')));
    await tester.pump();
    expect(repository.created.length, 1);
    expect(repository.created.single.amountPaise, 10050);
    expect(repository.created.single.paidPaise, 10050);
    expect(repository.created.single.paymentMode, 'cash');
    repository.createWait!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Open expense form'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'waiter can save an on-credit expense without creating a payment',
    (tester) async {
      final repository = FakeExpenseRepository();
      await openForm(tester, repository, role: UserRole.waiter);
      await fillBasics(tester);
      await tester.scrollUntilVisible(
        find.text('On credit'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('On credit'));
      await tester.pumpAndSettle();
      await reachSave(tester);
      await tester.tap(find.byKey(const Key('save-expense')));
      await tester.pumpAndSettle();
      expect(repository.created.single.paidPaise, 0);
      expect(repository.created.single.paymentMode, isNull);
    },
  );
  testWidgets('invalid partial payment is stopped before submission', (
    tester,
  ) async {
    final repository = FakeExpenseRepository();
    await openForm(tester, repository);
    await fillBasics(tester);
    await tester.scrollUntilVisible(
      find.text('Partly paid'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Partly paid'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('expense-partial')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('expense-partial')), '101');
    await reachSave(tester);
    await tester.tap(find.byKey(const Key('save-expense')));
    await tester.pumpAndSettle();
    expect(repository.created, isEmpty);
    expect(
      find.text(
        'A partial payment must be greater than zero and less than the expense amount.',
      ),
      findsOneWidget,
    );
  });
  testWidgets('connection-error retry preserves the draft and request ID', (
    tester,
  ) async {
    final repository = FakeExpenseRepository()..failCreate = true;
    await openForm(tester, repository);
    await fillBasics(tester);
    await reachSave(tester);
    await tester.tap(find.byKey(const Key('save-expense')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'We couldn’t save this entry. Check your connection and try again. Your form is still here.',
      ),
      findsOneWidget,
    );
    repository.failCreate = false;
    await tester.ensureVisible(find.byKey(const Key('save-expense')));
    await tester.tap(find.byKey(const Key('save-expense')));
    await tester.pumpAndSettle();
    expect(repository.created.length, 2);
    expect(repository.created.first.id, repository.created.last.id);
  });
  testWidgets(
    'waiter expense list switches only among server-provided eligible dates',
    (tester) async {
      final repository = FakeExpenseRepository();
      await mount(
        tester,
        repository,
        const ExpensesScreen(),
        role: UserRole.waiter,
      );
      expect(find.text('My expenses'), findsOneWidget);
      expect(repository.requestedDates, contains('2026-11-09'));
      await tester.tap(find.text('8 Nov 2026'));
      await tester.pumpAndSettle();
      expect(repository.requestedDates.last, '2026-11-08');
      expect(find.text('Groceries on credit'), findsOneWidget);
      expect(find.text('Choose an older date'), findsNothing);
    },
  );
  testWidgets('credit screen blocks waiter access before querying balances', (
    tester,
  ) async {
    final repository = FakeExpenseRepository();
    await mount(
      tester,
      repository,
      const CreditScreen(),
      role: UserRole.waiter,
    );
    expect(find.text('Administrator access required'), findsOneWidget);
    expect(repository.listCalls, 0);
  });
  testWidgets(
    'credit payment rejects overpay and records a valid partial payment',
    (tester) async {
      final repository = FakeExpenseRepository();
      await mount(tester, repository, const CreditScreen());
      await tester.ensureVisible(find.text('Record payment'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record payment'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('credit-payment-amount')),
        '1001',
      );
      await tester.ensureVisible(find.byKey(const Key('save-credit-payment')));
      await tester.tap(find.byKey(const Key('save-credit-payment')));
      await tester.pumpAndSettle();
      expect(
        find.text('Payment cannot exceed the outstanding amount.'),
        findsOneWidget,
      );
      expect(repository.payments, isEmpty);
      await tester.enterText(
        find.byKey(const Key('credit-payment-amount')),
        '500',
      );
      await tester.ensureVisible(find.byKey(const Key('save-credit-payment')));
      await tester.tap(find.byKey(const Key('save-credit-payment')));
      await tester.pumpAndSettle();
      expect(repository.payments.single.amountPaise, 50000);
      expect(repository.payments.single.date, '2026-11-09');
      expect(find.text('Remaining ₹500.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('expense form remains usable at small width and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    final repository = FakeExpenseRepository();
    await openForm(tester, repository);
    await reachSave(tester);
    expect(tester.takeException(), isNull);
  });
}
