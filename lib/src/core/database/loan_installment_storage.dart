part of 'app_database.dart';

const _loanTransactions = 'loan_installment/transactions';
const _loanTemplates = 'loan_installment/templates';
const _loanRules = 'loan_installment/rules';
const _loanSemanticsKey = 'loan_installment_semantics';
const _explicitLoanSemantics = 'explicit_v1';
typedef _LoanLinks = Map<String, Map<String, dynamic>>;

/// SQLite v9 keeps these sparse attributes in app_meta. Wire v3 carries them
/// on their owning rows. Reads and writes share the row's SQLite transaction.
extension _InstallmentStorage on AppDatabase {
  Future<_LoanLinks> _readLoanLinks(String key) async {
    final raw = await getMetaValue(key);
    if (raw == null) return {};
    final data = jsonDecode(raw) as Map<String, dynamic>;
    return data
        .map((id, fields) => MapEntry(id, fields as Map<String, dynamic>));
  }

  Future<void> _writeLoanLinks(String key, _LoanLinks links) => links.isEmpty
      ? deleteMetaValue(key)
      : setMetaValue(key, jsonEncode(links));

  Future<void> _replaceLoanLinks(
      String key, Iterable<model.LoanInstallmentFields> rows) async {
    final links = <String, Map<String, dynamic>>{};
    await _patchLoanLinks(key, links, rows, const [], replaceAll: true);
  }

  Future<void> _saveSeedLoanLinks(
      List<model.FinanceTransaction> entries) async {
    await _patchLoanLinks(_loanTransactions,
        await _readLoanLinks(_loanTransactions), entries, const []);
  }

  Future<void> _patchLoanLinks(String key, _LoanLinks links,
      Iterable<model.LoanInstallmentFields> rows, Iterable<String> removed,
      {bool replaceAll = false}) async {
    var changed = replaceAll;
    for (final id in removed) {
      if (links.remove(id) != null) changed = true;
    }
    final mappedAccounts = <String, Account>{};
    Future<Account> account(String id) async => mappedAccounts[id] ??=
        await (select(accounts)..where((r) => r.id.equals(id))).getSingle();
    for (final row in rows) {
      final fields = row.loanFields;
      if (fields.isEmpty) continue;
      if (row is model.FinanceTransaction &&
          (row.legacyLoanId != null || row.legacyLoanPartNumber != null)) {
        final loanId = row.legacyLoanId;
        final n = model.parseLoanInstallmentNumber(row.legacyLoanPartNumber);
        if (loanId == null ||
            n == null ||
            row.loanInstallmentNumber != null ||
            row.loanPaymentAmount != null ||
            !model.isLoanMoney(row.amount) ||
            (row.type != model.TransactionType.expense &&
                row.type != model.TransactionType.transfer) ||
            (row.type == model.TransactionType.transfer &&
                row.toAccountId != loanId) ||
            (row.type == model.TransactionType.expense &&
                row.toAccountId != null) ||
            row.accountId == loanId ||
            (await account(loanId)).accountType != 'loan') {
          throw const FormatException('旧还款分录关联无效。');
        }
        final unit = row.currency.trim().toUpperCase();
        if (unit != (await account(loanId)).currency.trim().toUpperCase() ||
            unit !=
                (await account(row.accountId)).currency.trim().toUpperCase() ||
            (row.type == model.TransactionType.transfer &&
                (unit != row.transferInCurrency.trim().toUpperCase() ||
                    (row.toAmount != null && row.toAmount != row.amount)))) {
          throw const FormatException('旧还款分录的币种或本金不匹配。');
        }
      } else {
        final n = model.parseLoanInstallmentNumber(row.loanInstallmentNumber);
        if (n == null ||
            row.type != model.TransactionType.transfer ||
            row.toAccountId == null ||
            row.toAccountId == row.accountId) {
          throw const FormatException('贷款还款缺少正确的期号或贷款目标。');
        }
        final source = await account(row.accountId);
        final target = await account(row.toAccountId!);
        final from = row.currency.trim().toUpperCase();
        final to = (row.toCurrency ?? row.currency).trim().toUpperCase();
        if (target.accountType != 'loan' ||
            from != source.currency.trim().toUpperCase() ||
            to != target.currency.trim().toUpperCase() ||
            !model.validLoanInstallmentAmounts(row.amount, row.toAmount,
                sameCurrency: from == to,
                loanPaymentAmount: row.loanPaymentAmount)) {
          throw const FormatException('贷款还款金额、币种或本金无效。');
        }
      }
      links[row.id] = fields;
      changed = true;
    }
    if (changed) await _writeLoanLinks(key, links);
  }

  Future<void> _migrateLegacyLoanLinks() async {
    final semantics = await getMetaValue(_loanSemanticsKey);
    if (semantics == _explicitLoanSemantics) return;
    if (semantics != null) throw FormatException('不支持的贷款分录版本：$semantics');
    final ledgerAccounts = {for (final a in await fetchAccounts()) a.id: a};
    final txs = await fetchTransactions();
    final templateRows = await fetchTransactionTemplates();
    final rules = await fetchRecurringTransactionRules();
    final combined = RegExp(r'^贷款月供 #([1-9][0-9]*)$');
    final principalPattern = RegExp(r'^贷款本金 #([1-9][0-9]*)$');
    final interestPattern = RegExp(r'^贷款利息 #([1-9][0-9]*)$');
    int? parseLabel(RegExp pattern, String? label) {
      final number =
          int.tryParse(pattern.firstMatch(label ?? '')?.group(1) ?? '');
      return number != null && number <= 9007199254740991 ? number : null;
    }

    bool hasLegacyPayer(model.LoanInstallmentFields row) {
      final source = ledgerAccounts[row.accountId];
      return source != null &&
          source.effectiveReportGroup == model.ReportGroup.cash &&
          source.currency.trim().toUpperCase() ==
              row.currency.trim().toUpperCase();
    }

    bool targetsSameCurrencyLoan(model.LoanInstallmentFields row) {
      final loan = ledgerAccounts[row.toAccountId];
      final from = row.currency.trim().toUpperCase();
      return row.type == model.TransactionType.transfer &&
          row.accountId != row.toAccountId &&
          loan?.accountType == model.AccountType.loan &&
          hasLegacyPayer(row) &&
          loan!.currency.trim().toUpperCase() == from &&
          (row.toCurrency ?? row.currency).trim().toUpperCase() == from;
    }

    for (final (key, rows) in <(String, Iterable<model.LoanInstallmentFields>)>[
      (_loanTransactions, txs),
      (_loanTemplates, templateRows),
      (_loanRules, rules)
    ]) {
      final links = await _readLoanLinks(key);
      for (final row in rows) {
        if (links.containsKey(row.id)) continue;
        final number = parseLabel(combined, row.description);
        if (number != null &&
            targetsSameCurrencyLoan(row) &&
            model.validLoanInstallmentAmounts(row.amount, row.toAmount)) {
          links[row.id] = {'loan_installment_number': number};
        }
      }

      if (key == _loanTransactions) {
        final pairs = <(String, DateTime, model.TransactionStatus, int),
            List<model.FinanceTransaction>>{};
        for (final tx in txs) {
          if (links.containsKey(tx.id) ||
              !model.isLoanMoney(tx.amount) ||
              !hasLegacyPayer(tx)) {
            continue;
          }
          final int? number;
          if (tx.type == model.TransactionType.transfer &&
              targetsSameCurrencyLoan(tx) &&
              (tx.toAmount == null || tx.toAmount == tx.amount)) {
            number = parseLabel(principalPattern, tx.description);
          } else if (tx.type == model.TransactionType.expense &&
              tx.toAccountId == null) {
            number = parseLabel(interestPattern, tx.description);
          } else {
            continue;
          }
          if (number == null) continue;
          final d = tx.transactionDate;
          (pairs[(
            tx.accountId,
            DateTime(d.year, d.month, d.day),
            tx.status,
            number
          )] ??= [])
              .add(tx);
        }
        for (final entry in pairs.entries) {
          final parts = entry.value;
          if (parts.length != 2 || parts.first.type == parts.last.type) {
            continue;
          }
          final principal = parts.first.type == model.TransactionType.transfer
              ? parts.first
              : parts.last;
          final interest = principal == parts.first ? parts.last : parts.first;
          if (principal.amount != 0 &&
              interest.amount != 0 &&
              principal.amount.isNegative != interest.amount.isNegative) {
            continue;
          }
          for (final part in parts) {
            links[part.id] = {
              'legacy_loan_id': principal.toAccountId!,
              'legacy_loan_part_number': entry.key.$4
            };
          }
        }
      }
      if (links.isNotEmpty) await _writeLoanLinks(key, links);
    }
    await setMetaValue(_loanSemanticsKey, _explicitLoanSemantics);
  }
}
