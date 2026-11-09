import 'package:flutter/material.dart';

abstract final class CategoryVisuals {
  static const icons = <String, IconData>{
    'category': Icons.category_outlined,
    'bakery': Icons.bakery_dining_outlined,
    'vegetables': Icons.eco_outlined,
    'grocery': Icons.shopping_basket_outlined,
    'dairy': Icons.water_drop_outlined,
    'salary': Icons.payments_outlined,
    'staff': Icons.groups_outlined,
    'conveyance': Icons.directions_car_outlined,
    'rent': Icons.storefront_outlined,
    'beverages': Icons.local_cafe_outlined,
    'frozen': Icons.ac_unit,
    'software': Icons.computer_outlined,
  };
  static const labels = <String, String>{
    'category': 'General',
    'bakery': 'Bakery',
    'vegetables': 'Vegetables',
    'grocery': 'Grocery',
    'dairy': 'Dairy',
    'salary': 'Salary',
    'staff': 'Staff Welfare',
    'conveyance': 'Conveyance',
    'rent': 'Rent',
    'beverages': 'Beverages',
    'frozen': 'Frozen',
    'software': 'Software',
  };

  static String readableName(String input) {
    var value = input
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match[1]} ${match[2]}',
        )
        .trim()
        .replaceAll(RegExp(r'[_\s]+'), ' ')
        .toLowerCase();
    if (value == 'veg' || value == 'veggies') return 'Vegetables';
    if (value == 'welfare exp staff' || value == 'welfare expense staff') {
      return 'Staff Welfare Expense';
    }
    value = value.replaceAll(RegExp(r'\bexp\b'), 'expense');
    return value
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }

  static String keyForName(String name) => switch (readableName(name)) {
    'Bakery' => 'bakery',
    'Vegetables' => 'vegetables',
    'Grocery' => 'grocery',
    'Dairy' => 'dairy',
    'Salary' => 'salary',
    'Staff Welfare Expense' => 'staff',
    'Conveyance' => 'conveyance',
    'Rent' => 'rent',
    'Beverages' => 'beverages',
    'Frozen' => 'frozen',
    'Software' => 'software',
    _ => 'category',
  };
  static IconData icon(String name, [String? key]) =>
      icons[key] ?? icons[keyForName(name)]!;
}
