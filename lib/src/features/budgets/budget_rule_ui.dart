import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/budget.dart';
import '../../core/providers/mutations/budget_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../shared/compass_ui.dart';

String budgetCategoryLabel(FinanceRepository repository, String categoryId) =>
    repository.categoryHierarchy
        .pathOf(categoryId)
        .map((c) => c.name)
        .join(' / ');

String budgetRuleDeletionMessage(
    FinanceRepository repository, Budget rule, String viewingMonth) {
  final others = repository.budgets
      .where((b) => b.categoryId == rule.categoryId && b.id != rule.id)
      .toList()
    ..sort((a, b) => a.monthKey.compareTo(b.monthKey));
  final previous =
      others.where((b) => b.monthKey.compareTo(rule.monthKey) < 0).lastOrNull;
  final next =
      others.where((b) => b.monthKey.compareTo(rule.monthKey) > 0).firstOrNull;
  final end = next == null ? '及以后' : '起至 ${next.monthKey} 新规则生效前';
  final fallback = previous == null
      ? '该类别在这段期间将没有独立预算。'
      : '这段期间将改用 ${previous.monthKey} 的规则（${compassMoney(previous.amount, currency: previous.currency)}）。';
  final inherited = viewingMonth != rule.monthKey
      ? '$viewingMonth 沿用了 ${rule.monthKey} 的预算。\n'
      : '';
  return '$inherited删除后，${rule.monthKey}$end的基础预算将重新计算。'
      '$fallback 后续结转也可能改变。';
}

Widget liveBudgetEditor(
    FinanceRepository initialRepository,
    Budget? source,
    Widget Function(
            FinanceRepository repository, Future<void> Function(Budget) persist)
        editor) {
  return Consumer(builder: (context, ref, _) {
    final repository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? initialRepository;
    return editor(
        repository,
        (budget) => ref
            .read(budgetMutationsProvider.notifier)
            .addBudget(budget, expectedSourceId: source?.id));
  });
}

Future<void> saveBudgetDraft(BuildContext context, Budget draft,
    Future<void> Function(Budget)? persist) async {
  try {
    if (persist != null) await persist(draft);
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存预算失败：$error')));
    }
    return;
  }
  if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
    Navigator.of(context).pop(draft);
  }
}
