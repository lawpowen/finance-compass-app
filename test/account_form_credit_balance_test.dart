import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/account_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Account _card(double balance) => Account(
      id: 'card',
      name: 'Card',
      accountType: AccountType.creditCard,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: balance,
      currentBalance: balance,
      creditLimit: 5000,
      statementDay: 25,
      paymentDueDay: 14,
    );

const _balanceField = Key('credit-card-balance-field');

/// Opens the form for [initial]; the returned getter reads the popped result.
Future<Account? Function()> _openForm(
  WidgetTester tester,
  Account initial,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Account? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildFinanceTheme(AppThemeStyle.abyss),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () async {
              result = await showDialog<Account>(
                context: context,
                builder: (_) => AccountFormDialog(initialAccount: initial),
              );
            },
            child: const Text('编辑信用卡'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('编辑信用卡'));
  await tester.pumpAndSettle();
  return () => result;
}

Future<void> _save(WidgetTester tester) async {
  // The form is a lazy ListView; the first Scrollable is its viewport.
  await tester.scrollUntilVisible(
    find.text('保存更改'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('保存更改'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('credit card balance field is signed and explained',
      (tester) async {
    await _openForm(tester, _card(-250));

    expect(find.text('信用卡余额'), findsOneWidget);
    expect(find.text('欠款填负数，溢缴款填正数'), findsOneWidget);
    expect(find.text('当前欠款'), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byKey(_balanceField)).controller!.text,
      '-250.00',
      reason: 'The stored signed balance is shown as-is, never flipped.',
    );
  });

  testWidgets('saving an untouched debt or overpayment keeps its sign',
      (tester) async {
    var result = await _openForm(tester, _card(-250));
    await _save(tester);
    expect(result()!.currentBalance, -250);

    result = await _openForm(tester, _card(80));
    await _save(tester);
    expect(result()!.currentBalance, 80);
  });

  testWidgets('edited debt stays negative and overpayment stays positive',
      (tester) async {
    var result = await _openForm(tester, _card(-250));
    await tester.enterText(find.byKey(_balanceField), '-300.5');
    await _save(tester);
    expect(result()!.currentBalance, -300.5);

    result = await _openForm(tester, _card(-250));
    await tester.enterText(find.byKey(_balanceField), '45');
    await _save(tester);
    expect(result()!.currentBalance, 45);
    expect(tester.takeException(), isNull);
  });

  testWidgets('non-finite credit card balance is rejected', (tester) async {
    final result = await _openForm(tester, _card(-250));
    for (final input in ['NaN', 'Infinity', '-Infinity']) {
      await tester.scrollUntilVisible(
        find.byKey(_balanceField),
        -300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.enterText(find.byKey(_balanceField), input);
      await _save(tester);
      await tester.scrollUntilVisible(
        find.byKey(_balanceField),
        -300,
        scrollable: find.byType(Scrollable).first,
      );

      expect(result(), isNull, reason: '$input must not be saved');
      expect(find.text('请输入有效金额'), findsOneWidget);
      expect(find.text('信用卡余额'), findsOneWidget);
    }
  });
}
