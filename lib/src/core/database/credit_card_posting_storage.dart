part of 'app_database.dart';

const _postingDatesKey = '${model.creditCardPostingMetaPrefix}transactions';

extension _CreditCardPostingStorage on AppDatabase {
  Future<Map<String, DateTime>> _readCardPostingDates() async {
    final raw = await getMetaValue(_postingDatesKey);
    if (raw == null) return {};
    final map = jsonDecode(raw);
    if (map is! Map<String, dynamic>) {
      throw const FormatException('信用卡入账日映射格式无效。');
    }
    return map.map((id, value) {
      final date = model.parseCardPostingDate(value);
      if (date == null) throw const FormatException('信用卡入账日映射包含空日期。');
      return MapEntry(id, date);
    });
  }

  /// Call inside the same write transaction as the owning transaction rows.
  Future<void> _patchCardPostingDates(
    Iterable<model.FinanceTransaction> entries, {
    Iterable<String> removed = const [],
  }) async {
    final posted = entries.where((entry) => entry.cardPostingDate != null);
    if (posted.isEmpty && removed.isEmpty) return;
    final dates = await _readCardPostingDates();
    var changed = false;
    for (final id in removed) {
      if (dates.remove(id) != null) changed = true;
    }
    if (posted.isNotEmpty) {
      final query = selectOnly(accounts)
        ..addColumns([accounts.id])
        ..where(accounts.accountType.equals(model.AccountType.creditCard.name));
      final cardIds =
          (await query.get()).map((r) => r.read(accounts.id)!).toSet();
      for (final entry in posted) {
        model.validateCardPostingDate(entry,
            sourceIsCreditCard: cardIds.contains(entry.accountId));
        dates[entry.id] = entry.cardPostingDate!;
        changed = true;
      }
    }
    if (!changed) return;
    if (dates.isEmpty) {
      await deleteMetaValue(_postingDatesKey);
    } else {
      await setMetaValue(
          _postingDatesKey,
          jsonEncode(dates.map(
              (id, date) => MapEntry(id, model.formatCardPostingDate(date)))));
    }
  }
}
