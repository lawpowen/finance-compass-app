import 'package:drift/native.dart';
import 'package:finance_app/src/core/database/app_database.dart'
    show AppDatabase;
import 'package:finance_app/src/core/models/category.dart';
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
