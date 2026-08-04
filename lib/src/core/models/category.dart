enum CategoryType {
  income,
  expense,
  investment,
  transfer,
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
    this.iconKey,
    this.colorValue,
    this.sortOrder = 0,
    this.isArchived = false,
  });

  final String id;
  final String name;
  final CategoryType type;
  final String? parentId;
  final String? iconKey;
  final int? colorValue;
  final int sortOrder;
  final bool isArchived;
}
