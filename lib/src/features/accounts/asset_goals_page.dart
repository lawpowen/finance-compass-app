import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/providers/mutations/account_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_colors.dart';
import '../shared/compass_ui.dart';

class AssetGoalsPage extends ConsumerWidget {
  const AssetGoalsPage({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRepository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? repository;
    // Goals are measured at the end of today: future-dated actual
    // transactions are not assets already held.
    final cutoff = activeRepository.assetGoalCutoffDate();
    final summaries = activeRepository.assetGoalSummaries(cutoffDate: cutoff);
    final history = activeRepository.totalAssetHistory(
      cutoffDate: cutoff,
      includeCredit: false,
    );
    final currentAssets = activeRepository.totalAssetsAt(
      cutoff,
      includeCredit: false,
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CompassBackground(
        child: SafeArea(
          child: ListView(
            padding: compassPagePadding,
            children: [
              CompassPageHeader(
                title: '资产目标',
                subtitle: '目标会按总资产变化自动更新进度',
                leading: const CompassBackButton(),
                actions: [
                  IconButton(
                    key: const Key('asset-goal-add'),
                    tooltip: '新增资产目标',
                    onPressed: () => _editGoal(context, ref),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              CompassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('当前总资产', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 5),
                    Text(
                      compassMoney(currentAssets),
                      style: const TextStyle(
                        color: FinanceColors.compassTeal,
                        fontSize: 30,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (history.length > 1) ...[
                      const SizedBox(height: 18),
                      CompassAreaChart(
                        values:
                            history.map((point) => point.totalAssets).toList(),
                        height: 120,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 22),
              CompassSectionTitle(
                '目标进度',
                trailing: Text('${summaries.length} 个目标'),
              ),
              const SizedBox(height: 10),
              if (summaries.isEmpty)
                CompassCard(
                  child: Column(
                    children: [
                      const CompassIconBadge(
                        icon: Icons.flag_outlined,
                        size: 48,
                        outlined: true,
                      ),
                      const SizedBox(height: 12),
                      const Text('还没有资产目标'),
                      const SizedBox(height: 5),
                      Text(
                        '设定目标后，这里会显示进度和首次达成日期。',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        key: const Key('asset-goal-empty-add'),
                        onPressed: () => _editGoal(context, ref),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('新增资产目标'),
                      ),
                    ],
                  ),
                )
              else
                ...summaries.map(
                  (summary) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _AssetGoalCard(
                      key: Key('asset-goal-${summary.goal.id}'),
                      summary: summary,
                      onEdit: () => _editGoal(
                        context,
                        ref,
                        initialGoal: summary.goal,
                      ),
                      onDelete: () => _deleteGoal(
                        context,
                        ref,
                        summary.goal,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editGoal(
    BuildContext context,
    WidgetRef ref, {
    AssetGoal? initialGoal,
  }) async {
    final nameController = TextEditingController(text: initialGoal?.name ?? '');
    final amountController = TextEditingController(
      text: initialGoal?.targetAmount.toStringAsFixed(2) ?? '',
    );
    final result = await showDialog<_AssetGoalDraft>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(initialGoal == null ? '新增资产目标' : '编辑资产目标'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('asset-goal-name'),
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: '目标名称'),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('asset-goal-amount'),
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: '目标金额'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const Key('asset-goal-save'),
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim());
              if (nameController.text.trim().isEmpty ||
                  amount == null ||
                  amount <= 0) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('请输入目标名称和大于 0 的金额。')),
                );
                return;
              }
              Navigator.pop(
                dialogContext,
                _AssetGoalDraft(
                  name: nameController.text.trim(),
                  amount: amount,
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    if (initialGoal == null) {
      await ref.read(accountMutationsProvider.notifier).addAssetGoal(
            name: result.name,
            amount: result.amount,
          );
    } else {
      await ref.read(accountMutationsProvider.notifier).updateAssetGoal(
            initialGoal.copyWith(
              name: result.name,
              targetAmount: result.amount,
            ),
          );
    }
  }

  Future<void> _deleteGoal(
    BuildContext context,
    WidgetRef ref,
    AssetGoal goal,
  ) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('删除资产目标'),
            content: Text('确定删除“${goal.name}”吗？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const Key('asset-goal-confirm-delete'),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await ref.read(accountMutationsProvider.notifier).deleteAssetGoal(goal.id);
  }
}

class _AssetGoalCard extends StatelessWidget {
  const _AssetGoalCard({
    super.key,
    required this.summary,
    required this.onEdit,
    required this.onDelete,
  });

  final AssetGoalProgressSummary summary;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ratio = summary.progressRatio.clamp(0.0, 1.0);
    final remaining = summary.goal.targetAmount - summary.currentAssets;
    return CompassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CompassIconBadge(
                icon: summary.isReached
                    ? Icons.flag_rounded
                    : Icons.flag_outlined,
                size: 40,
                color: summary.isReached
                    ? FinanceColors.compassTeal
                    : FinanceColors.compassOrange,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(summary.goal.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      '目标 ${compassMoney(summary.goal.targetAmount)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '管理目标',
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: ratio,
            minHeight: 9,
            borderRadius: BorderRadius.circular(8),
            color: summary.isReached
                ? FinanceColors.compassTeal
                : FinanceColors.compassOrange,
            backgroundColor: FinanceColors.compassBorder,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('${(summary.progressRatio * 100).toStringAsFixed(1)}%'),
              const Spacer(),
              Text(
                summary.isReached
                    ? '已达成${_reachedLabel(summary.reachedAt)}'
                    : '还差 ${compassMoney(remaining)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _reachedLabel(DateTime? date) {
    if (date == null) return '';
    return ' · ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

class _AssetGoalDraft {
  const _AssetGoalDraft({required this.name, required this.amount});

  final String name;
  final double amount;
}
