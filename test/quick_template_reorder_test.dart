import 'package:drift/native.dart';
import 'package:finance_app/src/core/data/finance_repository.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/providers/repository_provider.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/transactions/transaction_automation_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('template reorder persists a complete unique sort order', () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    var repository = await _repositoryWithTemplates(database);

    repository = await repository.reorderTransactionTemplates(
      ['tpl-5', 'tpl-0', 'tpl-1', 'tpl-2', 'tpl-3', 'tpl-4'],
    );

    expect(
      repository.transactionTemplates.map((item) => item.id),
      ['tpl-5', 'tpl-0', 'tpl-1', 'tpl-2', 'tpl-3', 'tpl-4'],
    );
    expect(
      repository.transactionTemplates.map((item) => item.sortOrder),
      [0, 1, 2, 3, 4, 5],
    );

    final reloaded = await FinanceRepository.load(database);
    expect(
      reloaded.transactionTemplates.map((item) => item.id),
      ['tpl-5', 'tpl-0', 'tpl-1', 'tpl-2', 'tpl-3', 'tpl-4'],
    );
  });

  testWidgets('quick-template manager drag promotes a template into top five',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = await _repositoryWithTemplates(database);
    final container = ProviderContainer(
      overrides: [
        financeRepositoryProvider.overrideWith(
          () => _TestRepositoryNotifier(repository),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildFinanceTheme(AppThemeStyle.abyss)
              .copyWith(splashFactory: NoSplash.splashFactory),
          home: QuickTemplateManagerPage(repository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(6));

    final list = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    list.onReorderItem!(5, 0);
    await tester.pumpAndSettle();

    final refreshed = await container.read(financeRepositoryProvider.future);
    expect(refreshed.transactionTemplates.first.id, 'tpl-5');
    expect(refreshed.transactionTemplates.take(5).map((item) => item.id),
        ['tpl-5', 'tpl-0', 'tpl-1', 'tpl-2', 'tpl-3']);
  });
}

Future<FinanceRepository> _repositoryWithTemplates(
  AppDatabase database,
) async {
  var repository = await FinanceRepository.load(database);
  repository = await repository.addAccount(
    const Account(
      id: 'cash',
      name: '现金账户',
      accountType: AccountType.cash,
      reportGroup: ReportGroup.cash,
      currency: 'MYR',
      currentBalance: 1000,
    ),
  );
  for (var index = 0; index < 6; index++) {
    repository = await repository.saveTransactionTemplate(
      TransactionTemplate(
        id: 'tpl-$index',
        name: '模板 $index',
        type: TransactionType.expense,
        accountId: 'cash',
        amount: 10 + index.toDouble(),
        currency: 'MYR',
        sortOrder: index,
      ),
    );
  }
  return repository;
}

class _TestRepositoryNotifier extends FinanceRepositoryNotifier {
  _TestRepositoryNotifier(this.repository);

  final FinanceRepository repository;

  @override
  Future<FinanceRepository> build() async => repository;
}
