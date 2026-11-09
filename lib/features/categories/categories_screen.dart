import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/status_panel.dart';
import '../../core/categories/category_visuals.dart';
import 'category_repository.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});
  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  String _search = '';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Expense categories')),
    body: ref
        .watch(categoriesProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => StatusPanel(
            icon: Icons.wifi_off_outlined,
            title: 'Unable to load categories',
            message: 'Check your connection and try again.',
            action: FilledButton(
              onPressed: () => ref.invalidate(categoriesProvider),
              child: const Text('Try again'),
            ),
          ),
          data: (categories) {
            final visible = categories
                .where(
                  (c) => c.name.toLowerCase().contains(_search.toLowerCase()),
                )
                .toList();
            return SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: 'Find a category',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (text) => setState(() => _search = text),
                    ),
                  ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(categoriesProvider);
                        await ref.read(categoriesProvider.future);
                      },
                      child: visible.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                StatusPanel(
                                  icon: Icons.category_outlined,
                                  title: categories.isEmpty
                                      ? 'No categories yet'
                                      : 'No matching categories',
                                  message: categories.isEmpty
                                      ? 'Your administrator can add expense categories.'
                                      : 'Try a different category name.',
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final category = visible[index];
                                return Card(
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 18,
                                      vertical: 8,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFFE8EFE8),
                                      child: Icon(
                                        CategoryVisuals.icon(
                                          category.name,
                                          category.iconKey,
                                        ),
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                    ),
                                    title: Text(
                                      CategoryVisuals.readableName(
                                        category.name,
                                      ),
                                    ),
                                    subtitle: category.active
                                        ? null
                                        : const Text('Inactive'),
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
  );
}
