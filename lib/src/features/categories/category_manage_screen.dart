import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/data/finance_repository.dart';
import '../../core/models/category.dart';
import '../../core/providers/mutations/category_mutations.dart';
import '../../core/providers/repository_provider.dart';
import '../../core/theme/finance_colors.dart';
import '../shared/compass_ui.dart';
import 'category_form_dialog.dart';

class CategoryManageScreen extends ConsumerStatefulWidget {
  const CategoryManageScreen({super.key, required this.repository});

  final FinanceRepository repository;

  @override
  ConsumerState<CategoryManageScreen> createState() =>
      _CategoryManageScreenState();
}

class _CategoryManageScreenState extends ConsumerState<CategoryManageScreen> {
  final searchController = TextEditingController();
  CategoryType? selectedType;

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository =
        ref.watch(financeRepositoryProvider).valueOrNull ?? widget.repository;
    final real = repository.sortedCategories();
    final query = searchController.text.trim().toLowerCase();
    final categories = real.where((item) {
      final typeMatch = selectedType == null || item.type == selectedType;
      final queryMatch =
          query.isEmpty || item.name.toLowerCase().contains(query);
      return typeMatch && queryMatch;
    }).toList();
    final expense =
        categories.where((item) => item.type == CategoryType.expense).toList();
    final income =
        categories.where((item) => item.type == CategoryType.income).toList();
    final investment = categories
        .where((item) => item.type == CategoryType.investment)
        .toList();
    final transfer =
        categories.where((item) => item.type == CategoryType.transfer).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CompassBackground(
        child: SafeArea(
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 94),
                children: [
                  Row(
                    children: [
                      const CompassBackButton(),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          '类别管理',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const Icon(Icons.search_rounded, size: 28),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _TypeTabBar(
                    selected: selectedType,
                    counts: {
                      null: real.length,
                      CategoryType.expense: real
                          .where((item) => item.type == CategoryType.expense)
                          .length,
                      CategoryType.income: real
                          .where((item) => item.type == CategoryType.income)
                          .length,
                      CategoryType.investment: real
                          .where((item) => item.type == CategoryType.investment)
                          .length,
                      CategoryType.transfer: real
                          .where((item) => item.type == CategoryType.transfer)
                          .length,
                    },
                    onChanged: (value) => setState(() => selectedType = value),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: '搜索类别',
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (selectedType == null ||
                      selectedType == CategoryType.expense)
                    _CategorySection(
                      title: '支出',
                      count: expense.length,
                      color: FinanceColors.compassOrange,
                      rows: expense
                          .map(
                            (item) => _CategoryPresentation.fromCategory(
                              item,
                              repository,
                            ),
                          )
                          .toList(),
                      onEdit: (row) {
                        if (row.source != null) {
                          _showEditCategory(context, row.source!);
                        }
                      },
                    ),
                  if (selectedType == null ||
                      selectedType == CategoryType.income)
                    _CategorySection(
                      title: '收入',
                      count: income.length,
                      color: FinanceColors.compassTeal,
                      rows: income
                          .map(
                            (item) => _CategoryPresentation.fromCategory(
                              item,
                              repository,
                            ),
                          )
                          .toList(),
                      onEdit: (row) {
                        if (row.source != null) {
                          _showEditCategory(context, row.source!);
                        }
                      },
                    ),
                  if (selectedType == null ||
                      selectedType == CategoryType.investment)
                    _CategorySection(
                      title: '投资',
                      count: investment.length,
                      color: FinanceColors.compassTeal,
                      rows: investment
                          .map(
                            (item) => _CategoryPresentation.fromCategory(
                              item,
                              repository,
                            ),
                          )
                          .toList(),
                      onEdit: (row) {
                        if (row.source != null) {
                          _showEditCategory(context, row.source!);
                        }
                      },
                    ),
                  if (selectedType == null ||
                      selectedType == CategoryType.transfer)
                    _CategorySection(
                      title: '转账',
                      count: transfer.length,
                      color: FinanceColors.compassTeal,
                      rows: transfer
                          .map(
                            (item) => _CategoryPresentation.fromCategory(
                              item,
                              repository,
                            ),
                          )
                          .toList(),
                      onEdit: (row) {
                        if (row.source != null) {
                          _showEditCategory(context, row.source!);
                        }
                      },
                    ),
                  const SizedBox(height: 18),
                  Text('ⓘ  已关联交易或预算的类别不可删除',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              Positioned(
                right: 18,
                bottom: 18,
                child: CompassActionBubble(
                  heroTag: 'category_add',
                  icon: Icons.add_rounded,
                  color: FinanceColors.compassOrange,
                  onPressed: () => _showAddCategory(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAddCategory(BuildContext context) async {
    final result = await showDialog<CategoryFormResult>(
      context: context,
      builder: (_) => const CategoryFormDialog(),
    );
    if (result != null) {
      await ref
          .read(categoryMutationsProvider.notifier)
          .addCategory(result.category);
    }
  }

  Future<void> _showEditCategory(
    BuildContext context,
    Category category,
  ) async {
    final result = await showDialog<CategoryFormResult>(
      context: context,
      builder: (_) => CategoryFormDialog(initialCategory: category),
    );
    if (result != null) {
      await ref
          .read(categoryMutationsProvider.notifier)
          .updateCategory(result.category);
    }
  }
}

class _TypeTabBar extends StatelessWidget {
  const _TypeTabBar({
    required this.selected,
    required this.counts,
    required this.onChanged,
  });
  final CategoryType? selected;
  final Map<CategoryType?, int> counts;
  final ValueChanged<CategoryType?> onChanged;

  @override
  Widget build(BuildContext context) {
    const values = <CategoryType?>[
      null,
      CategoryType.expense,
      CategoryType.income,
      CategoryType.investment,
      CategoryType.transfer,
    ];
    const labels = ['全部', '支出', '收入', '投资', '转账'];
    return Row(
      children: List.generate(values.length, (index) {
        final active = selected == values[index];
        return Expanded(
          child: InkWell(
            onTap: () => onChanged(values[index]),
            child: Container(
              padding: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    width: 2,
                    color:
                        active ? FinanceColors.compassTeal : Colors.transparent,
                  ),
                ),
              ),
              child: Text(
                '${labels[index]} ${counts[values[index]] ?? 0}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active
                      ? FinanceColors.compassTeal
                      : FinanceColors.compassMuted,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _CategorySection extends StatefulWidget {
  const _CategorySection({
    required this.title,
    required this.count,
    required this.color,
    required this.rows,
    required this.onEdit,
  });
  final String title;
  final int count;
  final Color color;
  final List<_CategoryPresentation> rows;
  final ValueChanged<_CategoryPresentation> onEdit;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  bool collapsed = false;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            expanded: !collapsed,
            child: InkWell(
              key: Key('category-section-${widget.title}'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => setState(() => collapsed = !collapsed),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: widget.color),
                    ),
                    const Spacer(),
                    Text('${widget.count} 个',
                        style: TextStyle(color: widget.color)),
                    Icon(
                      collapsed
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!collapsed) ...[
            const SizedBox(height: 8),
            ...widget.rows.map(
              (row) => _CategoryRow(
                row: row,
                onTap: () => widget.onEdit(row),
              ),
            ),
          ],
          const SizedBox(height: 20),
        ],
      );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.row, required this.onTap});
  final _CategoryPresentation row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: FinanceColors.compassBorder),
            ),
          ),
          child: Row(
            children: [
              CompassIconBadge(icon: row.icon, color: row.color, size: 38),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(row.name,
                        style: Theme.of(context).textTheme.titleMedium),
                    if (row.subtitle.isNotEmpty)
                      Text(row.subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      );
}

class _CategoryPresentation {
  const _CategoryPresentation({
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.source,
  });
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Category? source;

  factory _CategoryPresentation.fromCategory(
    Category category,
    FinanceRepository repository,
  ) {
    final count = repository.transactions
        .where((item) => item.categoryId == category.id)
        .length;
    return _CategoryPresentation(
      name: _translatedName(category.name),
      subtitle: '$count 笔交易',
      icon: _categoryIcon(category.iconKey, category.name),
      color: Color(category.colorValue ?? FinanceColors.compassTeal.toARGB32()),
      source: category,
    );
  }
}

String _translatedName(String name) {
  final lower = name.toLowerCase();
  if (lower.contains('food')) return '餐饮';
  if (lower.contains('transport')) return '交通';
  if (lower.contains('shopping')) return '购物';
  if (lower.contains('housing')) return '住房';
  if (lower.contains('salary')) return '工资';
  return name;
}

IconData _categoryIcon(String? key, String name) {
  final value = '${key ?? ''} $name'.toLowerCase();
  if (value.contains('restaurant') || value.contains('food')) {
    return Icons.restaurant_outlined;
  }
  if (value.contains('transport')) return Icons.directions_bus_outlined;
  if (value.contains('shopping')) return Icons.shopping_bag_outlined;
  if (value.contains('salary')) return Icons.badge_outlined;
  if (value.contains('home')) return Icons.home_outlined;
  return Icons.sell_outlined;
}
