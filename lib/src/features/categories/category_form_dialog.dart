import 'package:flutter/material.dart';

import '../shared/category_icons.dart';

import '../../core/models/category.dart';
import '../../core/models/category_hierarchy.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/theme/finance_theme.dart';
import '../../core/utils/id_generator.dart';
import '../shared/compass_ui.dart';

class CategoryFormResult {
  const CategoryFormResult({required this.category, required this.isEdit});
  final Category category;
  final bool isEdit;
}

class CategoryFormDialog extends StatefulWidget {
  const CategoryFormDialog({
    super.key,
    required this.categories,
    this.initialCategory,
    this.typeLocked = false,
  });

  final List<Category> categories;
  final Category? initialCategory;
  final bool typeLocked;

  @override
  State<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<CategoryFormDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final String categoryId;
  String? parentId;
  late CategoryType categoryType;
  late String iconKey;
  late int colorValue;
  late bool isArchived;

  bool get isEdit => widget.initialCategory != null;

  static const colors = [
    0xFF58D1C2,
    0xFFFF7A2C,
    0xFF7BAE8A,
    0xFF7A9FD0,
    0xFFB58BD5,
    0xFFE8A838,
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    nameController = TextEditingController(text: initial?.name ?? '');
    categoryId = initial?.id ?? buildId('cat');
    parentId = initial?.parentId;
    categoryType = initial?.type ?? CategoryType.expense;
    iconKey = initial?.iconKey ?? 'other';
    colorValue = initial?.colorValue ?? FinanceColors.compassTeal.toARGB32();
    isArchived = initial?.isArchived ?? false;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
    final hierarchy = CategoryHierarchy(widget.categories);
    final excluded = hierarchy.descendantsOf(categoryId);
    final typeLocked = widget.typeLocked ||
        widget.categories.any((category) => category.parentId == categoryId);
    final parentOptions = <Category?>[
      null,
      for (final category in hierarchy.ordered)
        if (category.type == categoryType &&
            (!category.isArchived ||
                category.id == widget.initialCategory?.parentId) &&
            !excluded.contains(category.id))
          category,
    ];
    final selectedParent =
        parentOptions.indexWhere((category) => category?.id == parentId);
    final invalidParent = selectedParent < 0;
    return Dialog.fullscreen(
      backgroundColor: Colors.transparent,
      child: CompassBackground(
        child: SafeArea(
          child: Form(
            key: formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 28),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isEdit ? '编辑类别' : '新增类别',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                    TextButton(
                      onPressed: invalidParent ? null : _submit,
                      child: const Text('保存'),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: color.withValues(alpha: .22),
                      child: Icon(
                          categoryIconChoices[iconKey] ??
                              Icons.category_outlined,
                          color: color,
                          size: 34),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nameController.text.isEmpty
                                ? '新类别'
                                : nameController.text,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _typeLabel(categoryType),
                            style: TextStyle(color: color),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const CompassSectionLabel('基本信息'),
                _CategoryEditorRow(
                  icon: Icons.edit_outlined,
                  title: '类别名称',
                  child: _CategoryTextField(
                    controller: nameController,
                    validator: (value) =>
                        value == null || value.trim().isEmpty ? '必填' : null,
                  ),
                ),
                _CategoryEditorRow(
                  icon: Icons.swap_vert_rounded,
                  title: '类别类型',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<CategoryType>(
                      value: categoryType,
                      alignment: Alignment.centerRight,
                      items: CategoryType.values
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(_typeLabel(type)),
                            ),
                          )
                          .toList(),
                      onChanged: typeLocked
                          ? null
                          : (value) {
                              if (value == null || value == categoryType) {
                                return;
                              }
                              setState(() {
                                categoryType = value;
                                if (hierarchy.byId[parentId]?.type != value) {
                                  parentId = null;
                                }
                              });
                            },
                    ),
                  ),
                ),
                if (typeLocked) const Text('类别已有关联记录或子类别，类型已锁定。'),
                _CategoryEditorRow(
                  icon: Icons.folder_outlined,
                  title: '父类别',
                  child: Semantics(
                    label: '选择父类别',
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        key: const Key('category-parent-picker'),
                        value: invalidParent ? null : selectedParent,
                        hint: const Text('请选择'),
                        alignment: AlignmentDirectional.centerEnd,
                        isExpanded: true,
                        menuMaxHeight: 360,
                        items: [
                          for (final (index, category) in parentOptions.indexed)
                            DropdownMenuItem(
                              value: index,
                              child: Text(
                                category == null
                                    ? '无父类别'
                                    : '${category.name}${category.isArchived ? '（已归档）' : ''}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (index) {
                          if (index != null) {
                            setState(() => parentId = parentOptions[index]?.id);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                if (invalidParent)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Text(
                      '原父类别无效，请选择现有类别或设为无父类别。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                _CategoryEditorRow(
                  icon: Icons.palette_outlined,
                  title: '图标与颜色',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: iconKey,
                      alignment: Alignment.centerRight,
                      items: {
                        ...categoryIconChoices,
                        if (!categoryIconChoices.containsKey(iconKey))
                          iconKey: Icons.category_outlined,
                      }
                          .entries
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(entry.value, color: color),
                                  const SizedBox(width: 8),
                                  Text(_iconLabel(entry.key)),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => iconKey = value);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: colors.map((value) {
                    final selected = value == colorValue;
                    return InkWell(
                      onTap: () => setState(() => colorValue = value),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(value),
                          border: Border.all(
                            color: selected ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: selected
                            ? const Icon(Icons.check_rounded, size: 18)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                if (isEdit)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('归档类别'),
                    subtitle: const Text('保留历史记录，但不再用于新增交易'),
                    value: isArchived,
                    onChanged: (value) => setState(() => isArchived = value),
                  ),
                const SizedBox(height: 24),
                CompassPrimaryButton(
                  label: '保存更改',
                  onPressed: invalidParent ? null : _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!formKey.currentState!.validate()) return;
    final initial = widget.initialCategory;
    Navigator.pop(
      context,
      CategoryFormResult(
        isEdit: isEdit,
        category: Category(
          id: categoryId,
          name: nameController.text.trim(),
          type: categoryType,
          parentId: parentId,
          iconKey: iconKey,
          colorValue: colorValue,
          sortOrder: initial?.sortOrder ?? 0,
          isArchived: isArchived,
        ),
      ),
    );
  }

  String _typeLabel(CategoryType type) => switch (type) {
        CategoryType.income => '收入',
        CategoryType.expense => '支出',
        CategoryType.investment => '投资',
        CategoryType.transfer => '转账',
      };

  String _iconLabel(String key) => switch (key) {
        'restaurant' => '餐饮',
        'transport' => '交通',
        'shopping' => '购物',
        'home' => '居家',
        'salary' => '薪资',
        'investment' => '投资',
        'transfer' => '转账',
        _ => '其他',
      };
}

class _CategoryEditorRow extends StatelessWidget {
  const _CategoryEditorRow({
    required this.icon,
    required this.title,
    required this.child,
  });
  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: financePaletteOf(context).border),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Icon(icon, color: financePaletteOf(context).seed),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
            SizedBox(width: 165, child: child),
          ],
        ),
      );
}

class _CategoryTextField extends StatelessWidget {
  const _CategoryTextField({
    required this.controller,
    this.validator,
  });
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        validator: validator,
        textAlign: TextAlign.right,
        decoration: const InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
      );
}
