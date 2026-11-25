import 'package:flutter/material.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/budget.dart';
import '../../core/models/category.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/id_generator.dart';
import '../../core/utils/month_key.dart';
import '../shared/compass_ui.dart';
import '../shared/finance_form_fields.dart';
import 'budget_rule_ui.dart';

class BudgetFormDialog extends StatefulWidget {
  const BudgetFormDialog({
    super.key,
    required this.repository,
    this.initialBudget,
    this.monthKey,
    this.persist,
  });

  final FinanceRepository repository;
  final Budget? initialBudget;
  final String? monthKey;
  final Future<void> Function(Budget)? persist;

  @override
  State<BudgetFormDialog> createState() => _BudgetFormDialogState();
}

class _BudgetFormDialogState extends State<BudgetFormDialog> {
  final formKey = GlobalKey<FormState>();
  final amountController = TextEditingController();
  final thresholdController = TextEditingController(text: '0.8');
  final monthController = TextEditingController(
    text: monthKeyFromDate(DateTime.now()),
  );

  List<Category> get categories {
    final initial = widget.initialBudget;
    return widget.repository.categoryOptions(
      CategoryType.expense,
      originalCategoryId: monthController.text.trim() == initial?.monthKey
          ? initial?.categoryId
          : null,
    );
  }

  String? categoryId;
  late String currency;
  bool rolloverEnabled = false;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final initialBudget = widget.initialBudget;
    currency = initialBudget?.currency ?? widget.repository.baseCurrency;
    monthController.text = widget.monthKey ??
        initialBudget?.monthKey ??
        monthKeyFromDate(DateTime.now());
    if (initialBudget != null) {
      categoryId = categories
          .where((c) => c.id == initialBudget.categoryId)
          .firstOrNull
          ?.id;
      amountController.text = initialBudget.amount.toString();
      thresholdController.text = initialBudget.alertThreshold.toString();
      rolloverEnabled = initialBudget.rolloverEnabled;
    } else if (categories.isNotEmpty) {
      categoryId = categories.first.id;
    }
    monthController.addListener(_monthChanged);
  }

  void _monthChanged() {
    setState(() {
      if (!categories.any((c) => c.id == categoryId)) categoryId = null;
    });
  }

  @override
  void didUpdateWidget(BudgetFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!categories.any((c) => c.id == categoryId)) categoryId = null;
  }

  @override
  void dispose() {
    amountController.dispose();
    thresholdController.dispose();
    monthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialBudget == null ? '新增预算' : '编辑预算'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: ValueKey(categoryId),
                  initialValue: categoryId,
                  validator: (id) =>
                      categories.any((c) => c.id == id) ? null : '请选择有效支出类别',
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '支出类别',
                    border: OutlineInputBorder(),
                  ),
                  items: categories
                      .map(
                        (category) => DropdownMenuItem(
                          value: category.id,
                          child: Text(
                              budgetCategoryLabel(
                                  widget.repository, category.id),
                              overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => categoryId = value),
                ),
                const SizedBox(height: 12),
                FinanceTextField(
                  controller: monthController,
                  label: '生效月份',
                  validator: (value) => RegExp(r'^\d{4}-(0[1-9]|1[0-2])$')
                          .hasMatch(value?.trim() ?? '')
                      ? null
                      : '格式 YYYY-MM',
                ),
                const SizedBox(height: 12),
                FinanceTextField(
                  isAmount: true,
                  controller: amountController,
                  label: '预算金额',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _numberRequired,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '预算币种',
                    border: OutlineInputBorder(),
                  ),
                  items: {...supportedCurrencies, currency}
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(currencyOptionLabel(item)),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => currency = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                FinanceTextField(
                  controller: thresholdController,
                  label: '提醒阈值',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: _numberRequired,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        value: rolloverEnabled,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('启用结转'),
                        onChanged: (value) =>
                            setState(() => rolloverEnabled = value),
                      ),
                    ),
                    const CompassHelpButton(
                      title: '预算结转',
                      message: '未用完的预算会加到下个月。超支的金额会扣减下个月的预算。',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
            onPressed: saving ? null : _submit, child: const Text('保存')),
      ],
    );
  }

  Future<void> _submit() async {
    if (saving) return;
    if (!formKey.currentState!.validate() || categoryId == null) {
      return;
    }

    final initial = widget.initialBudget;
    final sameRule = initial != null &&
        initial.categoryId == categoryId &&
        initial.monthKey == monthController.text.trim();
    final budget = Budget(
      id: sameRule ? initial.id : buildId('budget'),
      categoryId: categoryId!,
      monthKey: monthController.text.trim(),
      amount: double.parse(amountController.text.trim()),
      currency: currency,
      alertThreshold: double.parse(thresholdController.text.trim()),
      rolloverEnabled: rolloverEnabled,
    );
    setState(() => saving = true);
    await saveBudgetDraft(context, budget, widget.persist);
    if (mounted) setState(() => saving = false);
  }

  String? _numberRequired(String? value) {
    final number = double.tryParse(value?.trim() ?? '');
    return number == null || !number.isFinite || number <= 0
        ? '请输入大于 0 的有效数字'
        : null;
  }
}
