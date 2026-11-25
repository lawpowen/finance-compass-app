import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/features/accounts/credit_card_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Notifier extends FinanceRepositoryNotifier {
  _Notifier(this.repository);
  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}

Future<void> _openDetail(
  WidgetTester tester,
  DateTime reference, {
  int statementDay = 15,
  DateTime? purchaseDate,
}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final card = Account(
      id: 'card',
      name: 'Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      creditLimit: 1000,
      currentBalance: 0,
      statementDay: statementDay,
      paymentDueDay: 25);
  var repository = await FinanceRepository.load(db);
  repository = await repository.addAccount(card);
  repository = await repository.addTransaction(FinanceTransaction(
      id: 'purchase',
      type: TransactionType.expense,
      accountId: card.id,
      amount: 100,
      currency: 'MYR',
      transactionDate: purchaseDate ?? DateTime(2026, 11, 5)));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      financeRepositoryProvider.overrideWith(() => _Notifier(repository))
    ],
    child: MaterialApp(
        home: CreditCardDetailScreen(
            account: card, repository: repository, cutoffDate: reference)),
  ));
  await tester.pumpAndSettle();
}

Finder _insideTimeline(Finder matching) => find.descendant(
    of: find.byKey(const Key('credit-card-billing-timeline')),
    matching: matching);

Finder _dots({bool highlighted = false}) =>
    _insideTimeline(find.byWidgetPredicate((widget) {
      if (widget is! Container || widget.decoration is! BoxDecoration) {
        return false;
      }
      final decoration = widget.decoration! as BoxDecoration;
      return decoration.shape == BoxShape.circle &&
          (!highlighted || decoration.boxShadow?.isNotEmpty == true);
    }));

void main() {
  for (final (day, label, count, currentIndex) in [
    (15, '已结算 · 今天', 4, 1),
    (20, '今天', 5, 2),
    (25, '还款日 · 今天', 4, 2),
  ]) {
    testWidgets(
        'November $day contains one current calendar date and $count dots',
        (tester) async {
      await _openDetail(tester, DateTime(2026, 11, day, 17, 41));
      expect(_insideTimeline(find.text('11月$day日')), findsOneWidget);
      expect(_insideTimeline(find.text(label)), findsOneWidget);
      expect(_dots(), findsNWidgets(count));
      expect(_dots(highlighted: true), findsOneWidget);
      expect(tester.widget(_dots(highlighted: true)),
          same(tester.widget(_dots().at(currentIndex))));
      if (day == 25) {
        expect(_insideTimeline(find.text('今天到期')), findsOneWidget);
      }
    });
  }

  testWidgets(
      'coincident due and next statement keep both roles and selected statement hides today',
      (tester) async {
    await _openDetail(tester, DateTime(2026, 11, 25, 20),
        statementDay: 25, purchaseDate: DateTime(2026, 10, 2));
    expect(_insideTimeline(find.text('11月25日')), findsOneWidget);
    expect(_insideTimeline(find.text('还款日 · 下期结算 · 今天')), findsOneWidget);
    expect(_dots(), findsNWidgets(3));
    await tester.tap(find.text('查看账单'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('credit-card-statement-2026-10')));
    await tester.pumpAndSettle();
    expect(_insideTimeline(find.text('还款日 · 下期结算')), findsOneWidget);
    expect(_insideTimeline(find.textContaining('今天')), findsNothing);
    expect(_dots(), findsNWidgets(3));
    expect(_dots(highlighted: true), findsNothing);
  });
}
