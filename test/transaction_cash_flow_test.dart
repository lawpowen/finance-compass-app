import 'package:flutter_test/flutter_test.dart';

import 'package:finance_app/src/core/models/transaction.dart';
import 'package:finance_app/src/core/utils/transaction_cash_flow.dart';

void main() {
  final transfer = FinanceTransaction(
    id: 'transfer',
    type: TransactionType.transfer,
    accountId: 'cash',
    toAccountId: 'savings',
    amount: 120,
    currency: 'MYR',
    transactionDate: DateTime(2026, 7, 1),
  );

  test('subtracts an outgoing transfer for the source account', () {
    final effect = transferNetEffectTotal(
      [transfer],
      accountId: 'cash',
      outgoingAmountInBase: (transaction) => transaction.amount,
      incomingAmountInBase: (transaction) => transaction.transferInAmount,
    );

    expect(effect, -120);
  });

  test('adds an incoming transfer for the receiving account', () {
    final effect = transferNetEffectTotal(
      [transfer],
      accountId: 'savings',
      outgoingAmountInBase: (transaction) => transaction.amount,
      incomingAmountInBase: (transaction) => transaction.transferInAmount,
    );

    expect(effect, 120);
  });

  test('keeps internal transfers neutral without an account filter', () {
    final expense = FinanceTransaction(
      id: 'expense',
      type: TransactionType.expense,
      accountId: 'cash',
      amount: 40,
      currency: 'MYR',
      transactionDate: DateTime(2026, 7, 1),
    );

    final effect = transferNetEffectTotal(
      [transfer, expense],
      outgoingAmountInBase: (transaction) => transaction.amount,
      incomingAmountInBase: (transaction) => transaction.transferInAmount,
    );

    expect(effect, 0);
  });

  test('uses the incoming side amount for cross-currency transfers', () {
    final crossCurrencyTransfer = FinanceTransaction(
      id: 'fx-transfer',
      type: TransactionType.transfer,
      accountId: 'cash',
      toAccountId: 'overseas',
      amount: 150,
      currency: 'MYR',
      toAmount: 1000,
      toCurrency: 'TWD',
      transactionDate: DateTime(2026, 7, 1),
    );

    final effect = transferNetEffectTotal(
      [crossCurrencyTransfer],
      accountId: 'overseas',
      outgoingAmountInBase: (_) => 150,
      incomingAmountInBase: (_) => 140,
    );

    expect(effect, 140);
  });
}
