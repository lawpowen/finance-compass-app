import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/core/models/category_hierarchy.dart';
import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/budget.dart';
import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/models/transaction_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category writes reject missing parents and cycles atomically',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await expectLater(
      database.insertCategory(_category('orphan', parentId: 'missing')),
      throwsArgumentError,
    );
    await expectLater(
      database.insertCategory(_category('self', parentId: 'self')),
      throwsArgumentError,
    );
    expect(await database.fetchCategories(), isEmpty);

    await database.insertCategory(_category('root', archived: true));
    await database.insertCategory(_category('child', parentId: 'root'));
    await database.insertCategory(_category('leaf', parentId: 'child'));
    await expectLater(
      database.updateCategory(_category('root', parentId: 'leaf')),
      throwsArgumentError,
    );
    await expectLater(
      database.updateCategory(_category('child', parentId: 'missing')),
      throwsArgumentError,
    );
    final rows = await database.fetchCategories();
    expect(
      {for (final row in rows) row.id: row.parentId},
      {'root': null, 'child': 'root', 'leaf': 'child'},
    );
  });

  test(
      'category tree preserves sorted depth, paths and the closest active budget ancestor',
      () {
    final tree = CategoryHierarchy([
      _category('grandchild', parentId: 'child'),
      _category('root'),
      _category('child', parentId: 'root'),
      _category('archived', parentId: 'child', archived: true),
      _category('b'),
    ]);
    tree.validate();
    expect(tree.ordered.map((c) => c.id),
        ['b', 'root', 'child', 'archived', 'grandchild']);
    expect(tree.descendantsOf('child'), {'child', 'archived', 'grandchild'});
    expect(tree.pathOf('grandchild').map((c) => c.id),
        ['root', 'child', 'grandchild']);
    expect(tree.nearestAncestorIn('grandchild', {'root', 'child'}), 'child');
    expect(tree.nearestAncestorIn('grandchild', {'b'}), isNull);
    expect(tree.descendantsOf('deleted'), isEmpty);

    final broken = CategoryHierarchy(
        [_category('a', parentId: 'b'), _category('b', parentId: 'a')]);
    expect(broken.ordered, hasLength(2));
    expect(broken.descendantsOf('a'), {'a', 'b'});
    expect(broken.validate, throwsFormatException);
  });

  test(
      'linked category types and cross-type parenting are protected at the writer',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertAccount(const Account(
        id: 'cash',
        name: 'Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 200));
    for (final id in ['tx', 'budget', 'tpl', 'rule', 'parent', 'free']) {
      await db.insertCategory(_category(id));
    }
    final date = DateTime(2026, 4, 14);
    await db.insertTransaction(FinanceTransaction(
        id: 'e',
        type: TransactionType.expense,
        amount: 5,
        accountId: 'cash',
        currency: 'MYR',
        categoryId: 'tx',
        transactionDate: date));
    await db.upsertBudget(const Budget(
        id: 'b', categoryId: 'budget', monthKey: '2026-04', amount: 10));
    await db.replaceTransactionTemplates([
      const TransactionTemplate(
          id: 't',
          name: 'T',
          type: TransactionType.expense,
          accountId: 'cash',
          currency: 'MYR',
          amount: 2,
          categoryId: 'tpl')
    ]);
    await db.replaceRecurringTransactionRules([
      RecurringTransactionRule(
          id: 'r',
          name: 'R',
          type: TransactionType.expense,
          accountId: 'cash',
          currency: 'MYR',
          amount: 2,
          categoryId: 'rule',
          startDate: date)
    ]);
    await db.insertCategory(_category('child', parentId: 'parent'));
    for (final id in ['tx', 'budget', 'tpl', 'rule', 'parent']) {
      await expectLater(
          db.updateCategory(
              Category(id: id, name: id, type: CategoryType.income)),
          throwsArgumentError);
    }
    await db.updateCategory(
        const Category(id: 'free', name: 'Free', type: CategoryType.income));
    await expectLater(db.insertCategory(_category('invalid', parentId: 'free')),
        throwsArgumentError);
    await expectLater(db.updateCategory(_category('child', parentId: 'free')),
        throwsArgumentError);
    expect(
        (await db.fetchCategories())
            .singleWhere((c) => c.id == 'child')
            .parentId,
        'parent');
  });

  test(
      'archiving keeps old references editable but blocks new or copied selections',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await db.insertAccount(const Account(
        id: 'cash',
        name: 'Cash',
        accountType: AccountType.cash,
        reportGroup: ReportGroup.cash,
        currency: 'MYR',
        currentBalance: 100));
    await db.insertCategory(_category('archive'));
    final date = DateTime(2026, 4, 1);
    FinanceTransaction tx(String id, double amount) => FinanceTransaction(
        id: id,
        type: TransactionType.expense,
        amount: amount,
        accountId: 'cash',
        currency: 'MYR',
        categoryId: 'archive',
        transactionDate: date);
    Budget budget(String id, String month) =>
        Budget(id: id, categoryId: 'archive', monthKey: month, amount: 25);
    TransactionTemplate template(String id) =>
        TransactionTemplate.fromTransaction(
            id: id, name: 'Name', transaction: tx('unused', 1));
    RecurringTransactionRule rule(String id) =>
        RecurringTransactionRule.fromTransaction(
            id: id, name: 'Name', transaction: tx('unused', 1));
    await db.insertTransaction(tx('existing', 2));
    await db.upsertBudget(budget('existing', '2026-04'));
    await db.replaceTransactionTemplates([template('existing')]);
    await db.replaceRecurringTransactionRules([rule('existing')]);
    await db.updateCategory(_category('archive', archived: true));
    await db.updateTransaction(tx('existing', 3));
    await db.replaceTransactions(
        deleteIds: ['existing'], insertItems: [tx('existing', 4)]);
    await db.upsertBudget(budget('existing', '2026-04'));
    await db.replaceTransactionTemplates([template('existing')]);
    await db.replaceRecurringTransactionRules([rule('existing')]);
    await expectLater(
        db.insertTransaction(tx('copy', 10)), throwsArgumentError);
    await expectLater(
        db.upsertBudget(budget('copy', '2026-05')), throwsArgumentError);
    await expectLater(db.replaceTransactionTemplates([template('copy')]),
        throwsArgumentError);
    await expectLater(db.replaceRecurringTransactionRules([rule('copy')]),
        throwsArgumentError);
    expect((await db.fetchAccounts()).single.currentBalance, 96);
    expect((await db.fetchTransactionTemplates()).single.id, 'existing');
    expect((await db.fetchRecurringTransactionRules()).single.id, 'existing');
  });

  test('a child association prevents deletion until explicitly removed',
      () async {
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);

    await database.insertCategory(_category('root'));
    await database.insertCategory(
      _category('child', parentId: 'root', archived: true),
    );
    expect(await database.categoryHasLinkedData('root'), isTrue);
    expect(await database.deleteCategoryIfSafe('root'), isFalse);
    expect((await database.fetchCategories()).map((row) => row.id),
        unorderedEquals(['root', 'child']));

    await database.updateCategory(_category('child', archived: true));
    expect(await database.deleteCategoryIfSafe('root'), isTrue);
    expect((await database.fetchCategories()).single.id, 'child');
  });
}

Category _category(String id, {String? parentId, bool archived = false}) =>
    Category(
      id: id,
      name: id,
      type: CategoryType.expense,
      parentId: parentId,
      isArchived: archived,
    );
