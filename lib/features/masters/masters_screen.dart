import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/accounting/money.dart';
import '../../core/categories/category_visuals.dart';
import '../../core/widgets/status_panel.dart';
import '../authentication/auth_repository.dart';
import '../categories/category_repository.dart';
import '../expenses/expense_repository.dart';
import 'master_repository.dart';

class MastersScreen extends ConsumerStatefulWidget {
  const MastersScreen({super.key});
  @override
  ConsumerState<MastersScreen> createState() => _MastersScreenState();
}

class _MastersScreenState extends ConsumerState<MastersScreen> {
  MasterKind _kind = MasterKind.categories;
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final admin =
        ref.watch(profileProvider).asData?.value?.role == UserRole.admin;
    if (!admin) {
      return const Scaffold(
        body: StatusPanel(
          icon: Icons.lock_outline,
          title: 'Administrator access required',
          message: 'Return to your workspace.',
        ),
      );
    }
    final masters = ref.watch(masterDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cafe essentials')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: masters.asData == null
            ? null
            : () => _edit(masters.requireValue),
        icon: const Icon(Icons.add),
        label: Text(switch (_kind) {
          MasterKind.categories => 'Add category',
          MasterKind.vendors => 'Add vendor',
          MasterKind.items => 'Add item',
        }),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final kind in MasterKind.values)
                    ChoiceChip(
                      label: Text(switch (kind) {
                        MasterKind.categories => 'Categories',
                        MasterKind.vendors => 'Vendors',
                        MasterKind.items => 'Items',
                      }),
                      selected: _kind == kind,
                      onSelected: (_) => setState(() => _kind = kind),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Search by name',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: masters.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => StatusPanel(
                  icon: Icons.wifi_off_outlined,
                  title: 'Unable to load cafe essentials',
                  message: 'Check your connection and try again.',
                  action: FilledButton(
                    onPressed: () => ref.invalidate(masterDataProvider),
                    child: const Text('Try again'),
                  ),
                ),
                data: (data) {
                  final rows = data
                      .forKind(_kind)
                      .where(
                        (r) => r.name.toLowerCase().contains(
                          _search.toLowerCase(),
                        ),
                      )
                      .toList();
                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.invalidate(masterDataProvider);
                      await ref.read(masterDataProvider.future);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: rows.isEmpty ? 1 : rows.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (rows.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(30),
                            child: Text(
                              'No matching records. Use Add to create one.',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }
                        final row = rows[index];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 10,
                            ),
                            leading: _kind == MasterKind.categories
                                ? CircleAvatar(
                                    backgroundColor: const Color(0xFFE8EFE8),
                                    child: Icon(
                                      CategoryVisuals.icon(
                                        row.name,
                                        row.data['icon_key'] as String?,
                                      ),
                                    ),
                                  )
                                : null,
                            title: Text(
                              _kind == MasterKind.categories
                                  ? CategoryVisuals.readableName(row.name)
                                  : row.name,
                            ),
                            subtitle: Text(row.active ? 'Active' : 'Inactive'),
                            trailing: const Icon(Icons.edit_outlined),
                            onTap: () => _edit(data, record: row),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(MasterData data, {MasterRecord? record}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _MasterEditor(kind: _kind, data: data, record: record),
      ),
    );
    if (changed == true && mounted) {
      ref.invalidate(masterDataProvider);
      ref.invalidate(entryContextProvider);
      ref.invalidate(categoriesProvider);
    }
  }
}

class _MasterEditor extends ConsumerStatefulWidget {
  const _MasterEditor({required this.kind, required this.data, this.record});
  final MasterKind kind;
  final MasterData data;
  final MasterRecord? record;
  @override
  ConsumerState<_MasterEditor> createState() => _MasterEditorState();
}

class _MasterEditorState extends ConsumerState<_MasterEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name,
      _phone,
      _address,
      _notes,
      _unit,
      _rate;
  String? _category;
  String _iconKey = 'category';
  bool _iconChosen = false;
  bool _active = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final record = widget.record?.data;
    _name = TextEditingController(text: record?['name'] as String?);
    _iconKey =
        record?['icon_key'] as String? ??
        CategoryVisuals.keyForName(_name.text);
    _iconChosen =
        record?['icon_key'] != null && record?['icon_key'] != 'category';
    _phone = TextEditingController(text: record?['contact_number'] as String?);
    _address = TextEditingController(text: record?['address'] as String?);
    _notes = TextEditingController(text: record?['notes'] as String?);
    _unit = TextEditingController(text: record?['default_unit'] as String?);
    final rate = record?['default_rate_paise'] as int?;
    _rate = TextEditingController(
      text: rate == null
          ? ''
          : '${rate ~/ 100}.${(rate % 100).toString().padLeft(2, '0')}',
    );
    _category = record?['category_id'] as String?;
    _active = widget.record?.active ?? true;
  }

  @override
  void dispose() {
    for (final controller in [_name, _phone, _address, _notes, _unit, _rate]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    if (widget.record?.active == true && !_active) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Deactivate this record?'),
          content: const Text(
            'Existing financial entries will keep their references. This record will no longer be available for new expenses.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep active'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final values = <String, dynamic>{
      'name': widget.kind == MasterKind.categories
          ? CategoryVisuals.readableName(_name.text)
          : _name.text.trim(),
      'active': _active,
    };
    if (widget.kind == MasterKind.categories) values['icon_key'] = _iconKey;
    String? optional(TextEditingController controller) =>
        controller.text.trim().isEmpty ? null : controller.text.trim();
    if (widget.kind == MasterKind.vendors) {
      values.addAll({
        'contact_number': optional(_phone),
        'address': optional(_address),
        'notes': optional(_notes),
      });
    }
    if (widget.kind == MasterKind.items) {
      values.addAll({
        'category_id': _category,
        'default_unit': optional(_unit),
        'default_rate_paise': _rate.text.trim().isEmpty
            ? null
            : Money.parse(_rate.text).paise,
      });
    }
    try {
      await ref
          .read(masterRepositoryProvider)
          .save(widget.kind, values, id: widget.record?.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved successfully')));
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is PostgrestException && error.code == '23505'
              ? 'A record with that name already exists.'
              : 'Unable to save. Check the values and your connection, then try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = switch (widget.kind) {
      MasterKind.categories => 'category',
      MasterKind.vendors => 'vendor',
      MasterKind.items => 'item',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.record == null ? 'Add' : 'Edit'} $noun'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  maxLength: widget.kind == MasterKind.categories ? 100 : 120,
                  textCapitalization: TextCapitalization.words,
                  onChanged: widget.kind == MasterKind.categories
                      ? (name) {
                          if (!_iconChosen) {
                            setState(
                              () => _iconKey = CategoryVisuals.keyForName(name),
                            );
                          }
                        }
                      : null,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a name.'
                      : null,
                ),
                const SizedBox(height: 16),
                if (widget.kind == MasterKind.categories) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('category-icon/$_iconKey'),
                    initialValue: CategoryVisuals.icons.containsKey(_iconKey)
                        ? _iconKey
                        : 'category',
                    decoration: const InputDecoration(
                      labelText: 'Category icon',
                    ),
                    isExpanded: true,
                    items: CategoryVisuals.icons.entries
                        .map(
                          (entry) => DropdownMenuItem(
                            value: entry.key,
                            child: Row(
                              children: [
                                Icon(entry.value),
                                const SizedBox(width: 12),
                                Text(CategoryVisuals.labels[entry.key]!),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _iconKey = value ?? 'category';
                            _iconChosen = true;
                          }),
                  ),
                  const SizedBox(height: 16),
                ],
                if (widget.kind == MasterKind.vendors) ...[
                  TextFormField(
                    controller: _phone,
                    enabled: !_busy,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Contact number (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _address,
                    enabled: !_busy,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Address (optional)',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _notes,
                    enabled: !_busy,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                    ),
                  ),
                ],
                if (widget.kind == MasterKind.items) ...[
                  DropdownButtonFormField<String>(
                    initialValue: _category,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: widget.data
                        .forKind(MasterKind.categories)
                        .map(
                          (c) => DropdownMenuItem(
                            value: c.id,
                            child: Text(
                              '${c.name}${c.active ? '' : ' (inactive)'}',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _category = value),
                    validator: (value) =>
                        value == null ? 'Choose a category.' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _unit,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Default unit (optional)',
                      hintText: 'kg, litre, piece',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _rate,
                    enabled: !_busy,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Default rate (optional)',
                      prefixText: '₹ ',
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return null;
                      try {
                        Money.parse(value);
                        return null;
                      } on FormatException {
                        return 'Enter an amount with up to two decimal places.';
                      }
                    },
                  ),
                ],
                const SizedBox(height: 20),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  subtitle: const Text('Available for new entries'),
                  value: _active,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _active = value),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
