import 'package:flutter/material.dart';

import '../../core/models/category.dart';
import '../../core/theme/finance_colors.dart';
import '../../core/utils/id_generator.dart';
import '../shared/compass_ui.dart';

class CategoryFormResult {
  const CategoryFormResult({required this.category, required this.isEdit});
  final Category category;
  final bool isEdit;
}

class CategoryFormDialog extends StatefulWidget {
  const CategoryFormDialog({super.key, this.initialCategory});
  final Category? initialCategory;

  @override
  State<CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<CategoryFormDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController nameController;
  late final TextEditingController parentIdController;
  late CategoryType categoryType;
  late String iconKey;
  late int colorValue;
  late bool isArchived;

  bool get isEdit => widget.initialCategory != null;

  static const icons = <String, IconData>{
    'restaurant': Icons.restaurant_outlined,
    'transport': Icons.directions_bus_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'home': Icons.home_outlined,
    'salary': Icons.work_outline_rounded,
    'investment': Icons.trending_up_rounded,
    'transfer': Icons.swap_horiz_rounded,
    'other': Icons.category_outlined,
  };
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
    parentIdController = TextEditingController(text: initial?.parentId ?? '');
    categoryType = initial?.type ?? CategoryType.expense;
    iconKey = initial?.iconKey ?? 'other';
    colorValue = initial?.colorValue ?? FinanceColors.compassTeal.toARGB32();
    isArchived = initial?.isArchived ?? false;
  }

  @override
  void dispose() {
    nameController.dispose();
    parentIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);
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
                    TextButton(onPressed: _submit, child: const Text('保存')),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 34,
                      backgroundColor: color.withValues(alpha: .22),
                      child: Icon(icons[iconKey], color: color, size: 34),
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
                      onChanged: (value) {
                        if (value != null) setState(() => categoryType = value);
                      },
                    ),
                  ),
                ),
                _CategoryEditorRow(
                  icon: Icons.folder_outlined,
                  title: '父类别',
                  child: _CategoryTextField(
                    controller: parentIdController,
                    hintText: '可选父类别 ID',
                  ),
                ),
                _CategoryEditorRow(
                  icon: Icons.palette_outlined,
                  title: '图标与颜色',
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: iconKey,
                      alignment: Alignment.centerRight,
                      items: icons.entries
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
                const SizedBox(height: 18),
                Text('ⓘ  修改名称、图标或父类别不会影响已有记录',
                    style: Theme.of(context).textTheme.bodySmall),
                if (isEdit)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('归档类别'),
                    subtitle: const Text('保留历史记录，但不再用于新增交易'),
                    value: isArchived,
                    onChanged: (value) => setState(() => isArchived = value),
                  ),
                const SizedBox(height: 24),
                CompassPrimaryButton(label: '保存更改', onPressed: _submit),
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
          id: initial?.id ?? buildId('cat'),
          name: nameController.text.trim(),
          type: categoryType,
          parentId: parentIdController.text.trim().isEmpty
              ? null
              : parentIdController.text.trim(),
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
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: FinanceColors.compassBorder),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Icon(icon, color: FinanceColors.compassTeal),
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
    this.hintText,
  });
  final TextEditingController controller;
  final FormFieldValidator<String>? validator;
  final String? hintText;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        validator: validator,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          hintText: hintText,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
        ),
      );
}
