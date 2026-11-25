import 'category.dart';
import 'transaction.dart';

Set<CategoryType> allowedCategoryTypes(TransactionType type) => switch (type) {
      TransactionType.income => const {CategoryType.income},
      TransactionType.expense => const {CategoryType.expense},
      TransactionType.transfer || TransactionType.adjustment => const {
          CategoryType.transfer,
          CategoryType.investment
        },
    };

/// A ledger revision's category forest. Invalid legacy branches remain
/// inspectable so users can correct them; new snapshots use [validate].
class CategoryHierarchy {
  CategoryHierarchy(Iterable<Category> categories)
      : byId = Map.unmodifiable({for (final c in categories) c.id: c});

  final Map<String, Category> byId;
  late final Map<String?, List<Category>> _children = _indexChildren();
  late final List<Category> ordered = List.unmodifiable(_preorder());

  static int _compare(Category a, Category b) {
    final byType = a.type.name.compareTo(b.type.name);
    if (byType != 0) return byType;
    final byPosition = a.sortOrder.compareTo(b.sortOrder);
    if (byPosition != 0) return byPosition;
    final byName = a.name.compareTo(b.name);
    return byName == 0 ? a.id.compareTo(b.id) : byName;
  }

  Category? _parent(Category category) {
    final parent = byId[category.parentId];
    return parent?.type == category.type ? parent : null;
  }

  Map<String?, List<Category>> _indexChildren() {
    final children = <String?, List<Category>>{};
    for (final category in byId.values) {
      (children[_parent(category)?.id] ??= []).add(category);
    }
    for (final siblings in children.values) {
      siblings.sort(_compare);
    }
    return children;
  }

  Iterable<Category> _preorder() sync* {
    final seen = <String>{};
    final pending = [
      ...byId.values, // fallback for old cyclic branches with no root
      ...(_children[null] ?? const <Category>[]).reversed,
    ];
    while (pending.isNotEmpty) {
      final category = pending.removeLast();
      if (!seen.add(category.id)) continue;
      yield category;
      final children = _children[category.id];
      if (children != null) pending.addAll(children.reversed);
    }
  }

  Set<String> descendantsOf(String id) {
    final visited = <String>{};
    if (!byId.containsKey(id)) return visited;
    final pending = [id];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!visited.add(current)) continue;
      for (final child in _children[current] ?? const <Category>[]) {
        pending.add(child.id);
      }
    }
    return visited;
  }

  Iterable<Category> _ancestors(String? id) sync* {
    final visited = <String>{};
    var current = byId[id];
    while (current != null && visited.add(current.id)) {
      yield current;
      current = _parent(current);
    }
  }

  List<Category> pathOf(String id) => _ancestors(id).toList().reversed.toList();

  String? nearestAncestorIn(String? id, Set<String> candidates) {
    for (final category in _ancestors(id)) {
      if (candidates.contains(category.id)) return category.id;
    }
    return null;
  }

  /// Each edge is checked once even for deep hierarchies.
  void validate() {
    final checked = <String>{};
    for (final category in byId.values) {
      Category? current = category;
      final chain = <String>{};
      while (current != null && !checked.contains(current.id)) {
        if (!chain.add(current.id)) {
          throw FormatException('类别父级构成循环：${current.id}');
        }
        final parentId = current.parentId;
        if (parentId == null) break;
        final parent = byId[parentId];
        if (parent == null || parent.type != current.type) {
          throw FormatException('类别 ${current.id} 的父级不存在或类别类型不符。');
        }
        current = parent;
      }
      checked.addAll(chain);
    }
  }
}

/// Checks whether linking a category to this parent would lead into a cycle.
bool categoryParentWouldCycle(
  String childId,
  String proposedParentId,
  Map<String, String?> parents,
) {
  final visited = {childId};
  String? ancestor = proposedParentId;
  while (ancestor != null) {
    if (!visited.add(ancestor)) return true;
    ancestor = parents[ancestor];
  }
  return false;
}
