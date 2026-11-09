import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:topolina/core/categories/category_visuals.dart';

void main() {
  test('category labels use full readable names', () {
    expect(CategoryVisuals.readableName('veg'), 'Vegetables');
    expect(
      CategoryVisuals.readableName('Welfare Exp Staff'),
      'Staff Welfare Expense',
    );
    expect(
      CategoryVisuals.readableName('staffWelfareExpense'),
      'Staff Welfare Expense',
    );
    expect(CategoryVisuals.readableName('staff exp'), 'Staff Expense');
    expect(CategoryVisuals.readableName('  NEW_category '), 'New Category');
  });
  test('every seeded category has an icon and custom keys are respected', () {
    final categories = [
      'Bakery',
      'Vegetables',
      'Grocery',
      'Dairy',
      'Salary',
      'Staff Welfare Expense',
      'Conveyance',
      'Rent',
      'Beverages',
      'Frozen',
      'Software',
    ];
    for (final name in categories) {
      expect(CategoryVisuals.keyForName(name), isNot('category'));
    }
    expect(CategoryVisuals.icon('Custom', 'software'), Icons.computer_outlined);
    expect(
      CategoryVisuals.icon('Unknown', 'future-icon'),
      Icons.category_outlined,
    );
  });
}
