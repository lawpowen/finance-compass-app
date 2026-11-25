import '../data/finance_repository.dart';
import '../database/app_database.dart' show AppDatabase;
import '../models/category.dart';

/// Category queries share the ledger's hierarchy and historical-name fallback.
class CategoryService {
  CategoryService(
      {required List<Category> categories, required AppDatabase database})
      : this.fromRepository(FinanceRepository.fromSnapshot(
            database: database, categories: categories));
  const CategoryService.fromRepository(this.repository);

  final FinanceRepository repository;
  List<Category> categoriesByType(CategoryType type) =>
      repository.categoriesByType(type);
  List<Category> sortedCategories() => repository.sortedCategories();
  String categoryName(String id) => repository.categoryName(id);
  Future<bool> canDeleteCategory(String id) => repository.canDeleteCategory(id);
}
