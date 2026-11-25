import 'package:flutter/material.dart';

import '../../core/models/category.dart';

const categoryIconChoices = <String, IconData>{
  'restaurant': Icons.restaurant_outlined,
  'transport': Icons.directions_bus_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'home': Icons.home_outlined,
  'salary': Icons.work_outline_rounded,
  'investment': Icons.trending_up_rounded,
  'transfer': Icons.swap_horiz_rounded,
  'other': Icons.category_outlined,
};

// The original seed categories predate stored icon keys.
const _seedIconKeys = {
  'cat_food': 'restaurant',
  'cat_transport': 'transport',
  'cat_shopping': 'shopping',
  'cat_housing': 'home',
  'cat_salary': 'salary',
  'cat_invest': 'investment',
  'cat_transfer': 'transfer',
};

IconData categoryIcon(Category? category) =>
    categoryIconChoices[category?.iconKey ?? _seedIconKeys[category?.id]] ??
    Icons.category_outlined;
