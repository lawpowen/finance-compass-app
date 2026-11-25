import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/repository_provider.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/asset_snapshot.dart';
import '../shared/compass_ui.dart' show compassMoney;
import '../../core/utils/id_generator.dart';
import '../shared/finance_form_fields.dart';

class AssetSnapshotFormDialog extends StatelessWidget {
  const AssetSnapshotFormDialog({
    super.key,
    required this.repository,
    this.initialSnapshot,
    this.initialAccountId,
  });

  final FinanceRepository repository;
  final AssetSnapshot? initialSnapshot;
  final String? initialAccountId;

  @override
  Widget build(BuildContext context) {
    Widget editor(FinanceRepository live) => _SnapshotEditor(
        repository: live,
        initialSnapshot: initialSnapshot,
        initialAccountId: initialAccountId);
    final scope =
        context.getInheritedWidgetOfExactType<UncontrolledProviderScope>();
    if (scope == null) {
      return editor(repository);
    }
    return Consumer(builder: (context, ref, _) {
      final live =
          ref.watch(financeRepositoryProvider).valueOrNull ?? repository;
      if (!identical(live.database, repository.database)) {
        return AlertDialog(content: const Text('账本已切换，请重新打开快照。'), actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('返回')),
        ]);
      }
      return editor(live);
    });
  }
}

class _SnapshotEditor extends StatefulWidget {
  const _SnapshotEditor(
      {required this.repository, this.initialSnapshot, this.initialAccountId});
  final FinanceRepository repository;
  final AssetSnapshot? initialSnapshot;
  final String? initialAccountId;

  @override
  State<_SnapshotEditor> createState() => _SnapshotEditorState();
}

class _SnapshotEditorState extends State<_SnapshotEditor> {
  AssetSnapshot? _openingRecord;
  String? _suggestedText;

  @override
  void didUpdateWidget(_SnapshotEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.repository, widget.repository)) return;
    if (costBasisController.text == _suggestedText &&
        widget.repository.investmentAccounts().any((a) => a.id == accountId)) {
      _suggestBaseline();
    }
  }

  final formKey = GlobalKey<FormState>();
  late final TextEditingController marketValueController;
  late final TextEditingController cashBalanceController;
  late final TextEditingController costBasisController;

  late final String snapshotId;
  late DateTime snapshotDate;
  String? accountId;

  double get _marketValue =>
      double.tryParse(marketValueController.text.trim()) ?? 0;
  double get _cashBalance =>
      double.tryParse(cashBalanceController.text.trim()) ?? 0;
  double get _manualCostBasis =>
      double.tryParse(costBasisController.text.trim()) ?? 0;

  AssetSnapshot get _draft => AssetSnapshot(
        id: snapshotId,
        accountId: accountId!,
        snapshotDate: snapshotDate,
        marketValue: _marketValue,
        cashBalance: _cashBalance,
        costBasis: _manualCostBasis,
      );

  // Drift v9 persists whole seconds. Use that precision in the draft too,
  // so observations on the same day already use the persisted ID tie-break.
  static DateTime _endOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day, 23, 59, 59);

  void _suggestBaseline() {
    final id = accountId;
    if (id == null) return;
    final original = widget.initialSnapshot;
    final basis = original != null &&
            original.snapshotDate == snapshotDate &&
            widget.repository.snapshotSetsCostBaseline(original)
        ? original.costBasis
        : widget.repository.suggestedSnapshotBaseline(id, snapshotDate);
    _suggestedText = basis.toString();
    if (costBasisController.text != _suggestedText) {
      costBasisController.text = basis.toString();
    }
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialSnapshot;
    if (initial != null) {
      _openingRecord = widget.repository
              .snapshotsForAccount(initial.accountId)
              .where((s) => s.id == initial.id)
              .firstOrNull ??
          initial;
    }
    final investments = widget.repository.investmentAccounts();
    accountId = initial?.accountId ??
        widget.initialAccountId ??
        (investments.isNotEmpty ? investments.first.id : null);
    snapshotId = initial?.id ?? buildId('snap');
    snapshotDate = initial?.snapshotDate ?? _endOfDay(DateTime.now());
    marketValueController =
        TextEditingController(text: initial?.marketValue.toString() ?? '');
    cashBalanceController =
        TextEditingController(text: initial?.cashBalance.toString() ?? '0');
    costBasisController = TextEditingController(text: '0');
    _suggestBaseline();
    marketValueController.addListener(_refreshPreview);
    cashBalanceController.addListener(_refreshPreview);
    costBasisController.addListener(_refreshPreview);
  }

  @override
  void dispose() {
    marketValueController.removeListener(_refreshPreview);
    cashBalanceController.removeListener(_refreshPreview);
    costBasisController.removeListener(_refreshPreview);
    marketValueController.dispose();
    cashBalanceController.dispose();
    costBasisController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final investments = widget.repository.investmentAccounts();
    final account = investments.where((a) => a.id == accountId).firstOrNull;
    final currency = account?.currency ?? widget.repository.baseCurrency;
    final original = _openingRecord;
    final changed = original != null &&
        !original.matchesObservation(widget.repository
            .snapshotsForAccount(original.accountId)
            .where((s) => s.id == original.id)
            .firstOrNull);
    final draft = account == null ? null : _draft;
    final valuation =
        draft == null ? null : widget.repository.snapshotValuation(draft);
    final canEditBaseline =
        draft != null && widget.repository.snapshotSetsCostBaseline(draft);
    final timeLabel = snapshotDate.hour == 23 &&
            snapshotDate.minute == 59 &&
            snapshotDate.second == 59
        ? '日终'
        : '${snapshotDate.hour.toString().padLeft(2, '0')}:${snapshotDate.minute.toString().padLeft(2, '0')}:${snapshotDate.second.toString().padLeft(2, '0')}';
    String nativeAmount(double value) =>
        compassMoney(value, currency: currency);
    return AlertDialog(
      title: Text(widget.initialSnapshot == null ? '更新市值' : '编辑市值记录'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: account?.id,
                  key: ValueKey(account?.id),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '投资账户',
                    border: OutlineInputBorder(),
                  ),
                  items: investments
                      .map((account) => DropdownMenuItem(
                            value: account.id,
                            child: Text(
                              '${account.name} · ${account.currency}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: widget.initialSnapshot == null &&
                          widget.initialAccountId == null
                      ? (value) {
                          setState(() {
                            accountId = value;
                            _suggestBaseline();
                          });
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('快照日期'),
                  subtitle: Text(
                    '${snapshotDate.year}-${snapshotDate.month.toString().padLeft(2, '0')}-${snapshotDate.day.toString().padLeft(2, '0')} · $timeLabel',
                  ),
                  trailing: TextButton(
                    onPressed: _pickDate,
                    child: const Text('修改'),
                  ),
                ),
                const SizedBox(height: 12),
                FinanceTextField(
                  isAmount: true,
                  controller: marketValueController,
                  label: '账户总市值',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _numberRequired,
                ),
                const SizedBox(height: 12),
                FinanceTextField(
                  isAmount: true,
                  controller: cashBalanceController,
                  label: '账户现金余额',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _numberRequired,
                ),
                if (canEditBaseline) ...[
                  const SizedBox(height: 12),
                  FinanceTextField(
                    isAmount: true,
                    controller: costBasisController,
                    label: '快照日投入本金基准',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: _numberRequired,
                  ),
                ],
                const SizedBox(height: 12),
                if (changed || account == null)
                  Text(changed ? '这条快照已修改或删除，请重新打开后编辑。' : '请选择当前账本中的投资账户。'),
                if (valuation != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color:
                          Theme.of(context).cardColor.withValues(alpha: 0.72),
                      border: Border.all(color: Theme.of(context).cardColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('自动计算',
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text(
                            '累计投入成本 ${nativeAmount(valuation.cumulativeCost)}'),
                        const SizedBox(height: 4),
                        Text('净投入 ${nativeAmount(valuation.netInvestment)}'),
                        const SizedBox(height: 4),
                        Text('资金净收益 ${nativeAmount(valuation.gain)}'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消')),
        FilledButton(
            onPressed: changed || account == null ? null : _submit,
            child: const Text('保存')),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: snapshotDate,
      firstDate: DateTime(snapshotDate.year < 1 ? snapshotDate.year : 1),
      lastDate:
          DateTime(snapshotDate.year > 9999 ? snapshotDate.year : 9999, 12, 31),
    );
    if (picked != null && mounted && _endOfDay(picked) != snapshotDate) {
      setState(() {
        snapshotDate = _endOfDay(picked);
        _suggestBaseline();
      });
    }
  }

  void _submit() {
    if (!formKey.currentState!.validate() || accountId == null) {
      return;
    }

    final valuation = widget.repository.snapshotValuation(_draft);
    Navigator.of(context).pop(
      AssetSnapshot(
        id: snapshotId,
        accountId: accountId!,
        snapshotDate: snapshotDate,
        marketValue: _marketValue,
        costBasis: valuation.netInvestment,
        cashBalance: _cashBalance,
        unrealizedPnl: valuation.gain,
      ),
    );
  }

  void _refreshPreview() {
    if (mounted) {
      setState(() {});
    }
  }

  String? _numberRequired(String? value) =>
      double.tryParse(value ?? '')?.isFinite == true ? null : '请输入有效金额';
}
