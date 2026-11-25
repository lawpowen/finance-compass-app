import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/features/transactions/transactions_v2_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _LedgerNotifier extends FinanceRepositoryNotifier {
  _LedgerNotifier(this.initial);
  final FinanceRepository initial;
  @override
  Future<FinanceRepository> build() async => initial;
}

Future<ProviderContainer> _ledger(List<String> names) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  var repo = await FinanceRepository.load(db);
  repo = await repo.addAccount(const Account(
    id: 'cash',
    name: '钱包',
    accountType: AccountType.cash,
    reportGroup: ReportGroup.cash,
    currency: 'MYR',
    currentBalance: 1000,
  ));
  final day = DateTime.now();
  repo = await repo.addTransactions([
    for (final (i, name) in names.indexed)
      FinanceTransaction(
        id: 'expense-$i',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 10,
        currency: 'MYR',
        merchant: name,
        transactionDate: DateTime(day.year, day.month, 1, 9, i),
      ),
  ]);
  final scope = ProviderContainer(overrides: [
    financeRepositoryProvider.overrideWith(() => _LedgerNotifier(repo)),
  ]);
  addTearDown(scope.dispose);
  return scope;
}

Future<
    ({
      ProviderContainer inner,
      ProviderContainer outer,
      ModalRoute<void> search
    })> _open(WidgetTester tester, List<String> names) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final outer = await _ledger(['外部账本']);
  final inner = await _ledger(names);
  final repo = await inner.read(financeRepositoryProvider.future);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: outer,
    child: MaterialApp(
        home: UncontrolledProviderScope(
      container: inner,
      child: Scaffold(body: TransactionsV2Screen(repository: repo)),
    )),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('搜索交易'));
  await tester.pumpAndSettle();
  final field = find.byType(TextField);
  await tester.enterText(field, '咖啡');
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
  final search = ModalRoute.of<void>(tester.element(field))!;
  return (inner: inner, outer: outer, search: search);
}

void _stillSearching(WidgetTester tester, ModalRoute<void> search) {
  expect(search.isCurrent, isTrue,
      reason: 'The original search route must remain current');
  expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text, '咖啡');
  expect(find.text('外部账本'), findsNothing);
}

Finder _resultScroll() => find.descendant(
    of: find.byType(ListView), matching: find.byType(Scrollable));

Future<void> _menu(WidgetTester tester, String name) async {
  final row =
      find.ancestor(of: find.text(name), matching: find.byType(InkWell)).first;
  await tester.tap(find.descendant(of: row, matching: find.byTooltip('交易操作')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('删除'));
  await tester.pumpAndSettle();
}

void main() {
  // Each widget fixture opens a separate outer and inner ledger on purpose.
  setUp(() {
    final previous = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(
        () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previous);
  });

  testWidgets(
      'search long press deletes only selected results and retains the scrolled query',
      (tester) async {
    final names = [
      for (var i = 0; i < 35; i++) '咖啡 ${i.toString().padLeft(2, '0')}',
      '杂货'
    ];
    final fixture = await _open(tester, names);
    expect(find.text('杂货'), findsNothing);
    final scroll = _resultScroll();
    final position = tester.state<ScrollableState>(scroll).position;
    position.jumpTo(position.maxScrollExtent / 2);
    await tester.pumpAndSettle();
    final originalOffset = position.pixels;
    expect(originalOffset, greaterThan(100));
    final visible = find
        .textContaining(RegExp(r'^咖啡 \d\d$'))
        .hitTestable()
        .evaluate()
        .map((element) => (element.widget as Text).data!)
        .toList();
    expect(visible.length, greaterThan(3));
    final first = visible[1], second = visible[2];
    await tester.longPress(find.text(first));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 笔'), findsOneWidget);
    await tester.tap(find.text(second));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 笔'), findsOneWidget);
    await tester.tap(find.byTooltip('删除所选交易'));
    await tester.pumpAndSettle();
    expect(find.text('删除 2 笔交易？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 笔'), findsOneWidget);
    expect(
        (await fixture.inner.read(financeRepositoryProvider.future))
            .transactions
            .length,
        names.length);
    await tester.tap(find.byTooltip('删除所选交易'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    _stillSearching(tester, fixture.search);
    expect(tester.state<ScrollableState>(_resultScroll()).position.pixels,
        closeTo(originalOffset, 1));
    expect(find.text(first), findsNothing);
    expect(find.text(second), findsNothing);
    final saved = await fixture.inner.read(financeRepositoryProvider.future);
    expect(saved.transactions.map((t) => t.merchant),
        unorderedEquals(names.where((n) => n != first && n != second)));
    expect(
        saved.accounts.single.currentBalance, 1000 - (names.length - 2) * 10);
    expect(
        (await fixture.outer.read(financeRepositoryProvider.future))
            .accounts
            .single
            .currentBalance,
        990);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'single row and editor deletion both return to the same search, including empty results',
      (tester) async {
    final fixture = await _open(tester, ['咖啡 A', '咖啡 B', '杂货']);
    await _menu(tester, '咖啡 A');
    expect(find.text('删除 1 笔交易？'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    _stillSearching(tester, fixture.search);
    expect(find.text('咖啡 A'), findsOneWidget);

    await _menu(tester, '咖啡 A');
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    _stillSearching(tester, fixture.search);
    expect(find.text('咖啡 A'), findsNothing);
    await tester.tap(find.text('咖啡 B'));
    await tester.pumpAndSettle();
    expect(find.text('编辑交易'), findsOneWidget);
    await tester.ensureVisible(find.text('删除交易'));
    await tester.tap(find.text('删除交易'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    _stillSearching(tester, fixture.search);
    expect(find.text('咖啡 B'), findsNothing);
    expect(find.text('杂货'), findsNothing);
    expect(find.text('没有匹配的交易'), findsOneWidget);
    final saved = await fixture.inner.read(financeRepositoryProvider.future);
    expect(saved.transactions.single.merchant, '杂货');
    expect(saved.accounts.single.currentBalance, 990);
    expect(
        (await fixture.outer.read(financeRepositoryProvider.future))
            .transactions
            .single
            .merchant,
        '外部账本');
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.byTooltip('搜索交易'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'search reconciles selected IDs on a live ledger revision and Back exits selection',
      (tester) async {
    final fixture = await _open(tester, ['咖啡 A', '咖啡 B', '杂货']);
    await tester.longPress(find.text('咖啡 A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('咖啡 B'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 笔'), findsOneWidget);
    await fixture.inner
        .read(financeRepositoryProvider.notifier)
        .mutate((repo) async {
      final reduced = await repo.deleteExistingTransactions(['expense-0']);
      return reduced.addTransaction(FinanceTransaction(
          id: 'updated-result',
          type: TransactionType.expense,
          accountId: 'cash',
          amount: 12,
          currency: 'MYR',
          merchant: '咖啡 C',
          transactionDate: DateTime.now()));
    });
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 笔'), findsOneWidget);
    expect(find.text('咖啡 A'), findsNothing);
    expect(find.text('咖啡 B'), findsOneWidget);
    expect(find.text('咖啡 C'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    _stillSearching(tester, fixture.search);
    expect(find.text('已选择 1 笔'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
