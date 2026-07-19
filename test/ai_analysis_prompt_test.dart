import 'package:finance_app/src/core/services/ai_analysis_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('external AI prompt defines three distinct financial lenses', () {
    final prompt = AiAnalysisService.buildAnalysisPrompt({
      'base_currency': 'MYR',
      'future_month_count': 6,
    });

    expect(prompt, contains('消费发生'));
    expect(prompt, contains('现金收付'));
    expect(prompt, contains('信用负债'));
    expect(prompt, contains('信用卡还款是 transfer，不是消费支出'));
    expect(prompt, contains('投资市值调整不是工资或经营收入'));
    expect(prompt, contains('未来已确定'));
    expect(prompt, contains('planned 始终单列为预计'));
    expect(prompt, contains('完整备份 JSON'));
    expect(prompt, contains('base_currency 是 MYR'));
    expect(prompt, contains('未来 6 个月'));
  });

  test('analysis request advertises the v3 calculation contract', () {
    const source = AiAnalysisService.financeAnalysisSystemPrompt;

    expect(source, contains('transaction_date 是经济事项发生日期'));
    expect(source, contains('现金账户之间转账净额为零'));
    expect(source, contains('当前已确定负债'));
    expect(source, contains('future actual/settled 与 future planned 必须分列'));
  });
}
