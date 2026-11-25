import 'package:finance_app/src/core/models/account.dart';
import 'package:finance_app/src/core/models/loan_amortization.dart';
import 'package:finance_app/src/core/settings/app_theme_style.dart';
import 'package:finance_app/src/core/theme/finance_theme.dart';
import 'package:finance_app/src/features/accounts/account_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Account _loan(DateTime contract, DateTime tracking) => Account(
      id: 'loan',
      name: 'Loan',
      accountType: AccountType.loan,
      reportGroup: ReportGroup.credit,
      currency: 'MYR',
      initialBalance: -1000,
      currentBalance: -1000,
      loanPrincipal: 1000,
      loanAnnualInterestRate: 3.875,
      loanStartDate: contract,
      loanTrackingStartDate: tracking,
      loanTermMonths: 12,
      loanPaymentDay: 10,
      loanRepaymentMethod: LoanRepaymentMethod.flatRate,
    );

Future<Account? Function()> _open(WidgetTester tester, Account account) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(600, 1100);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  Account? saved;
  await tester.pumpWidget(MaterialApp(
    theme: buildFinanceTheme(AppThemeStyle.abyss),
    home: Builder(
        builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  saved = await showDialog<Account>(
                      context: context,
                      builder: (_) =>
                          AccountFormDialog(initialAccount: account));
                },
                child: const Text('Edit loan'),
              ),
            )),
  ));
  await tester.tap(find.text('Edit loan'));
  await tester.pumpAndSettle();
  return () => saved;
}

Future<void> _tapInForm(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder.hitTestable(), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
  await tester.tap(finder.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _acceptDate(WidgetTester tester) async {
  final dialog = find.byType(DatePickerDialog);
  final ok = MaterialLocalizations.of(tester.element(dialog)).okButtonLabel;
  await tester.tap(find.descendant(of: dialog, matching: find.text(ok)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renaming an existing loan retains the exact annual rate',
      (tester) async {
    final result = await _open(
        tester, _loan(DateTime(2026, 6, 10), DateTime(2026, 6, 12)));
    await tester.enterText(find.byType(TextFormField).first, 'Renamed');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await _tapInForm(tester, find.text('保存更改'));
    expect(result()?.name, 'Renamed');
    expect(result()?.loanAnnualInterestRate, 3.875);
  });

  testWidgets(
      'moving contract date forward moves the tracking date and first due month',
      (tester) async {
    final result = await _open(
        tester, _loan(DateTime(2026, 6, 10), DateTime(2026, 6, 12)));
    await _tapInForm(tester, find.byKey(const Key('loan-contract-date')));
    final dialog = find.byType(DatePickerDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('15')));
    await tester.pumpAndSettle();
    await _acceptDate(tester);
    await _tapInForm(tester, find.byKey(const Key('loan-tracking-date')));
    final picker = tester.widget<DatePickerDialog>(dialog);
    expect(picker.firstDate, DateTime(2026, 6, 15));
    expect(picker.initialDate, picker.firstDate);
    await _acceptDate(tester);
    await _tapInForm(tester, find.text('保存更改'));
    expect(result()?.loanStartDate, DateTime(2026, 6, 15));
    expect(result()?.loanTrackingStartDate, DateTime(2026, 6, 15));
    expect(
        tryCalculateLoanScheduleForAccount(result()!)!
            .installments
            .first
            .dueDate,
        DateTime(2026, 7, 10));
  });

  testWidgets(
      'an inconsistent legacy tracking date remains repairable in the picker',
      (tester) async {
    final account = _loan(DateTime(2250, 2, 1, 12), DateTime(2249));
    expect(tryCalculateLoanScheduleForAccount(account), isNull);
    final result = await _open(tester, account);
    await _tapInForm(tester, find.byKey(const Key('loan-tracking-date')));
    final picker =
        tester.widget<DatePickerDialog>(find.byType(DatePickerDialog));
    expect(picker.initialDate, DateTime(2250, 2, 1));
    expect(picker.lastDate, picker.initialDate);
    await _acceptDate(tester);
    await _tapInForm(tester, find.text('保存更改'));
    expect(result()?.loanTrackingStartDate, DateTime(2250, 2, 1));
    expect(tryCalculateLoanScheduleForAccount(result()!), isNotNull);
  });
}
