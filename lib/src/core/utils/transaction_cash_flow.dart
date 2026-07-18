import '../models/transaction.dart';

double transferNetEffectTotal(
  Iterable<FinanceTransaction> transactions, {
  String? accountId,
  required double Function(FinanceTransaction transaction) outgoingAmountInBase,
  required double Function(FinanceTransaction transaction) incomingAmountInBase,
}) {
  if (accountId == null) return 0;

  return transactions.where((transaction) {
    return transaction.type == TransactionType.transfer;
  }).fold<double>(0, (total, transaction) {
    var effect = 0.0;
    if (transaction.accountId == accountId) {
      effect -= outgoingAmountInBase(transaction);
    }
    if (transaction.toAccountId == accountId) {
      effect += incomingAmountInBase(transaction);
    }
    return total + effect;
  });
}
