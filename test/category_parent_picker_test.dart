import 'package:finance_app/src/core/models/category.dart';
import 'package:finance_app/src/features/categories/category_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _archived = Category(
  id: 'archived-id',
  name: 'Archived bucket',
  type: CategoryType.expense,
  isArchived: true,
);
const _current = Category(
  id: 'current-id',
  name: 'Current bucket',
  type: CategoryType.expense,
  parentId: 'archived-id',
);
const _child = Category(
  id: 'child-id',
  name: 'Descendant bucket',
  type: CategoryType.expense,
  parentId: 'current-id',
);
const _income = Category(
  id: 'income-id',
  name: 'Income bucket',
  type: CategoryType.income,
);

final _parentPicker = find.byKey(const Key('category-parent-picker'));
final _save = find.widgetWithText(TextButton, '保存');

void main() {
  testWidgets(
      'referenced parent is locked and cannot select a descendant or income parent',
      (tester) async {
    CategoryFormResult? result;
    await _openEditor(tester,
        initial: _current, onResult: (value) => result = value);
    final type = tester.widget<DropdownButton<CategoryType>>(
        find.byType(DropdownButton<CategoryType>));
    expect(type.onChanged, isNull);
    expect(find.text('Archived bucket（已归档）'), findsOneWidget);
    await tester.tap(_parentPicker);
    await tester.pumpAndSettle();
    expect(find.text('Income bucket'), findsNothing);
    expect(find.text('Descendant bucket'), findsNothing);
    expect(find.widgetWithText(DropdownMenuItem<int>, 'Current bucket'),
        findsNothing);
    await tester.tap(find.text('Archived bucket（已归档）').last);
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(result?.category.parentId, _archived.id);
    expect(result?.category.type, CategoryType.expense);
  });

  testWidgets('changing an unused category type clears an incompatible parent',
      (tester) async {
    CategoryFormResult? result;
    await _openEditor(tester,
        initial: _child, onResult: (value) => result = value);
    await tester.tap(find.byType(DropdownButton<CategoryType>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('收入').last);
    await tester.pumpAndSettle();
    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(result?.category.type, CategoryType.income);
    expect(result?.category.parentId, isNull);
  });

  testWidgets('requires an explicit choice for a missing legacy parent',
      (tester) async {
    CategoryFormResult? result;
    await _openEditor(
      tester,
      initial: const Category(
        id: 'legacy-id',
        name: 'Legacy bucket',
        type: CategoryType.expense,
        parentId: 'free text that is not an ID',
      ),
      onResult: (picked) => result = picked,
    );

    final invalidMessage = find.textContaining('原父类别无效');
    expect(invalidMessage, findsOneWidget);
    expect(tester.widget<TextButton>(_save).onPressed, isNull);

    await tester.tap(_parentPicker);
    await tester.pumpAndSettle();
    await tester.tap(find.text('无父类别').last);
    await tester.pumpAndSettle();
    expect(invalidMessage, findsNothing);

    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    expect(result!.category.parentId, isNull);
  });

  testWidgets('saves a selected parent ID, while showing category names',
      (tester) async {
    CategoryFormResult? result;
    await _openEditor(tester, onResult: (picked) => result = picked);
    await tester.enterText(find.byType(TextFormField), 'New bucket');
    await tester.tap(_parentPicker);
    await tester.pumpAndSettle();
    expect(find.text('Archived bucket（已归档）'), findsNothing);
    expect(find.text('Income bucket'), findsNothing);
    await tester.tap(find.text('Current bucket').last);
    await tester.pumpAndSettle();

    await tester.tap(_save);
    await tester.pumpAndSettle();
    expect(result?.category.parentId, _current.id);
  });
}

Future<void> _openEditor(
  WidgetTester tester, {
  Category? initial,
  required ValueChanged<CategoryFormResult?> onResult,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            onResult(await showDialog<CategoryFormResult>(
              context: context,
              builder: (_) => CategoryFormDialog(
                categories: const [_archived, _current, _child, _income],
                initialCategory: initial,
              ),
            ));
          },
          child: const Text('打开表单'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('打开表单'));
  await tester.pumpAndSettle();
}
