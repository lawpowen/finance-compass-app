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
