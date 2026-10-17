import '../models/transaction.dart';

class NotificationMatch {
  const NotificationMatch(
      {this.amount,
      this.currency,
      this.type,
      this.reference,
      this.merchant,
      required this.reason});
  final double? amount;
  final String? currency;
  final TransactionType? type;
  final String? reference;
  final String? merchant;
  final String reason;
  bool get isClear => reason.isEmpty;
}

/// Conservative parser: unknown templates are reviewable, never guessed.
NotificationMatch parsePaymentNotification(String text) {
  final money = RegExp(
          r'\b(MYR|RM|USD|CNY|TWD)\s*([0-9]+(?:,[0-9]{3})*\.[0-9]{2})(?![0-9])',
          caseSensitive: false)
      .allMatches(text)
      .toList();
  final single = money.length == 1 ? money.single : null;
  final amount =
      single == null ? null : double.tryParse(single[2]!.replaceAll(',', ''));
  final currency = single?[1]?.toUpperCase().replaceAll('RM', 'MYR');
  NotificationMatch uncertain(String reason) =>
      NotificationMatch(amount: amount, currency: currency, reason: reason);
  if (RegExp(
          r'\b(otp|tac|verification|verify|failed|declined|pending|refund|reversal|reversed|transfer|repayment|due|request|authorization|authorisation|preauth|cashback|reward)\b|验证码|退款|转账|还款|预授权|失败|待处理',
          caseSensitive: false)
      .hasMatch(text)) {
    return uncertain('验证码、失败或特殊交易，需要人工确认');
  }
  if (single == null || amount == null || !amount.isFinite || amount <= 0) {
    return uncertain('缺少唯一且有效的金额与币种');
  }
  // Exact sentence shapes intentionally exclude promotional/conditional text.
  final payment = RegExp(
          r'^(?:Payment of|Paid) (?:MYR|RM|USD|CNY|TWD) [0-9,]+\.[0-9]{2} to (.{1,100}?) (?:was successful|successfully)\.?\s+(?:Ref|Reference|Transaction ID):\s*([A-Za-z0-9-]{6,64})(?:\s+Card:\s*[*xX]*[0-9]{4})?\.?$',
          caseSensitive: false)
      .firstMatch(text.trim());
  final income = RegExp(
          r'^Received (?:MYR|RM|USD|CNY|TWD) [0-9,]+\.[0-9]{2} from (.{1,100}?) successfully\.?\s+(?:Ref|Reference|Transaction ID):\s*([A-Za-z0-9-]{6,64})(?:\s+Account:\s*[*xX]*[0-9]{4})?\.?$',
          caseSensitive: false)
      .firstMatch(text.trim());
  final match = payment ?? income;
  if (match == null) return uncertain('通知格式尚未验证，或缺少明确成功状态/交易编号');
  return NotificationMatch(
      amount: amount,
      currency: currency,
      type: payment != null ? TransactionType.expense : TransactionType.income,
      merchant: match[1],
      reference: match[2],
      reason: '');
}
