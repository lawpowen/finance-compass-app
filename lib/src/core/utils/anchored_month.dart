const recurringOccurrenceMetaPrefix = 'recurring-occurrence/';

String occurrenceKeyPrefix(String ruleId) =>
    '$recurringOccurrenceMetaPrefix${Uri.encodeComponent(ruleId)}/';

String occurrenceKey(String ruleId, String transactionId) =>
    '${occurrenceKeyPrefix(ruleId)}${Uri.encodeComponent(transactionId)}';

final _validMonth = RegExp(r'^\d{4}-(0[1-9]|1[0-2])$');
bool isRecurringMonthKey(Object? value) =>
    value is String && _validMonth.hasMatch(value);

String recurringMonthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

String recurringInstanceId(String ruleId, String monthKey) =>
    'txn_recurring_${ruleId}_$monthKey';

/// The instance's contractual month survives changes to its occurrence date.
String nominalOccurrenceMonth(
    String ruleId, String id, DateTime date, String? registered) {
  final prefix = 'txn_recurring_${ruleId}_';
  if (id.startsWith(prefix)) {
    final key = id.substring(prefix.length);
    if (isRecurringMonthKey(key)) return key;
  }
  return registered ?? recurringMonthKey(date);
}

/// Advances by calendar months, keeping the original day wherever it exists.
DateTime anchoredMonthDate(DateTime anchor, int offset) {
  final create = anchor.isUtc ? DateTime.utc : DateTime.new;
  final last = create(anchor.year, anchor.month + offset + 1, 0);
  return create(
      last.year,
      last.month,
      anchor.day.clamp(1, last.day),
      anchor.hour,
      anchor.minute,
      anchor.second,
      anchor.millisecond,
      anchor.microsecond);
}

/// Future occurrences of a calendar-day rule, in (after, through].
/// Jump directly to the visible months even if the rule began years ago.
Iterable<DateTime> recurringDates({
  required DateTime start,
  required int intervalMonths,
  required DateTime after,
  required DateTime through,
  DateTime? end,
}) sync* {
  if (intervalMonths < 1) return;
  final anchor = DateTime(start.year, start.month, start.day);
  final lower = DateTime(after.year, after.month, after.day);
  final upperBound = end != null && end.isBefore(through) ? end : through;
  final upper = DateTime(upperBound.year, upperBound.month, upperBound.day);
  final lastOffset =
      (upper.year - anchor.year) * 12 + upper.month - anchor.month;
  final firstOffset =
      (lower.year - anchor.year) * 12 + lower.month - anchor.month;
  var offset =
      firstOffset <= 0 ? 0 : (firstOffset ~/ intervalMonths) * intervalMonths;
  while (offset <= lastOffset) {
    final date = anchoredMonthDate(anchor, offset);
    if (date.isAfter(lower) && !date.isAfter(upper)) yield date;
    if (lastOffset - offset < intervalMonths) break;
    offset += intervalMonths;
  }
}
