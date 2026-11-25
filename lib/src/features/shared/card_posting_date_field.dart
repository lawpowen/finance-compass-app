import 'package:flutter/material.dart';

import '../../core/models/account.dart';
import '../../core/models/credit_card_billing.dart';

/// An optional posting day for the source card's statement.
class CardPostingDateField extends StatelessWidget {
  const CardPostingDateField({
    super.key,
    required this.source,
    required this.transactionDate,
    required this.value,
    required this.onChanged,
    this.repayment = false,
  });

  final Account source;
  final DateTime transactionDate;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool repayment;

  @override
  Widget build(BuildContext context) {
    final posting = value;
    final detail = posting == null
        ? (repayment ? '跟随还款日期' : '跟随交易日期')
        : '${posting.year}年${posting.month}月${posting.day}日';
    final statementDay = source.statementDay;
    final cut = statementDay == null
        ? null
        : creditCardChargeStatementDate(
            posting ?? transactionDate, statementDay);
    final billingMonth = cut == null
        ? null
        : calculateCreditCardBillingPeriodForStatement(
            statementDay: statementDay!,
            paymentDueDay: source.paymentDueDay ?? statementDay,
            statementDate: cut,
          ).billingMonthDate;
    return Row(
      children: [
        Expanded(
          child: ListTile(
            key: const Key('card-posting-date-picker'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(repayment ? '转出卡入账日' : '账单入账日'),
            subtitle: Text(billingMonth == null
                ? detail
                : '$detail · 计入 ${billingMonth.month}月账单'),
            onTap: () async {
              final first = DateUtils.dateOnly(transactionDate);
              final selected = await showDatePicker(
                context: context,
                firstDate: first,
                initialDate: posting ?? first,
                lastDate: DateTime(9999, 12, 31),
              );
              if (selected != null && context.mounted) onChanged(selected);
            },
          ),
        ),
        if (posting != null)
          TextButton(
            key: const Key('card-posting-date-clear'),
            onPressed: () => onChanged(null),
            child: const Text('恢复默认'),
          )
        else if (cut != null)
          Flexible(
            child: TextButton(
              key: const Key('card-posting-date-shortcut'),
              onPressed: () =>
                  onChanged(DateTime(cut.year, cut.month, cut.day + 1)),
              child: Text(repayment ? '顺延至转出卡下期账单' : '顺延至下期账单'),
            ),
          ),
      ],
    );
  }
}
