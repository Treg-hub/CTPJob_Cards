import 'package:flutter/material.dart';
import '../utils/persona_audit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ink_recipe.dart';
import '../models/ink_stock_item.dart';
import '../providers/current_employee_provider.dart';
import '../providers/ink_provider.dart';
import '../utils/role.dart' as role_utils;
import '../utils/screen_insets.dart';

/// Manager screen (1e): list + curate production recipes.
class InkRecipeManagementScreen extends ConsumerWidget {
  const InkRecipeManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isManager = role_utils.isInkManager(ref.watch(currentEmployeeProvider).valueOrNull);
    if (!isManager) {
      return Scaffold(
        appBar: AppBar(title: const Text('Recipes')),
        body: const Center(child: Text('Manager access required.')),
      );
    }

    final recipesAsync = ref.watch(inkAllRecipesProvider);
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final names = {for (final i in items) i.itemCode: i.displayName};

    return Scaffold(
      appBar: AppBar(title: const Text('Recipes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const InkRecipeEditScreen())),
        icon: const Icon(Icons.add),
        label: const Text('New recipe'),
      ),
      body: recipesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (recipes) => recipes.isEmpty
            ? const Center(child: Text('No recipes yet. Tap New recipe.'))
            : ListView.separated(
                padding: ScreenInsets.listPadding(context, horizontal: 16, top: 8),
                itemCount: recipes.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = recipes[i];
                  return ListTile(
                    title: Text(r.name,
                        style: TextStyle(
                            color: r.active
                                ? null
                                : Theme.of(context).disabledColor)),
                    subtitle: Text(
                        '→ ${names[r.outputItemCode] ?? r.outputItemCode} · '
                        '${r.inputs.length} inputs · v${r.version}'
                        '${r.active ? '' : ' · inactive'}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => InkRecipeEditScreen(recipe: r))),
                  );
                },
              ),
      ),
    );
  }
}

class _InputRow {
  _InputRow({this.itemCode, String qty = ''})
      : qtyCtrl = TextEditingController(text: qty);
  String? itemCode;
  final TextEditingController qtyCtrl;
}

/// Add or edit a recipe (manager).
class InkRecipeEditScreen extends ConsumerStatefulWidget {
  const InkRecipeEditScreen({super.key, this.recipe});
  final InkRecipe? recipe;

  @override
  ConsumerState<InkRecipeEditScreen> createState() => _EditState();
}

class _EditState extends ConsumerState<InkRecipeEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _outputPerPotCtrl;
  String? _outputItemCode;
  late bool _active;
  late List<_InputRow> _rows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.recipe;
    _nameCtrl = TextEditingController(text: r?.name ?? '');
    _outputPerPotCtrl =
        TextEditingController(text: r != null ? r.outputPerPot.toString() : '');
    _outputItemCode = r?.outputItemCode;
    _active = r?.active ?? true;
    _rows = r?.inputs
            .map((l) => _InputRow(
                itemCode: l.itemCode, qty: l.qtyPerPot.toString()))
            .toList() ??
        [_InputRow()];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _outputPerPotCtrl.dispose();
    for (final row in _rows) {
      row.qtyCtrl.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!guardPersonaSubmit(context)) return;
    if (!_formKey.currentState!.validate() || _outputItemCode == null) return;
    final inputs = <InkRecipeLine>[];
    for (final row in _rows) {
      final qty = double.tryParse(row.qtyCtrl.text.trim());
      if (row.itemCode == null || qty == null || qty <= 0) continue;
      inputs.add(InkRecipeLine(itemCode: row.itemCode!, qtyPerPot: qty));
    }
    if (inputs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Add at least one input line.')));
      return;
    }
    setState(() => _saving = true);
    final recipe = (widget.recipe ??
            const InkRecipe(name: '', outputItemCode: '', outputPerPot: 0))
        .copyWith(
      name: _nameCtrl.text.trim(),
      outputItemCode: _outputItemCode,
      outputPerPot: double.parse(_outputPerPotCtrl.text.trim()),
      inputs: inputs,
      active: _active,
    );
    try {
      await ref.read(inkServiceProvider).saveRecipe(recipe);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inkStockItemsProvider).valueOrNull ?? [];
    final outputs = items
        .where((i) => i.itemClass == InkItemClass.manufactured)
        .toList();
    final inputCandidates =
        items.where((i) => i.itemCode != _outputItemCode).toList();

    return Scaffold(
      appBar: AppBar(
          title: Text(widget.recipe == null ? 'New Recipe' : 'Edit Recipe')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: ScreenInsets.symmetricScroll(context),
          children: [
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Recipe name'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a name' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _outputItemCode,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Produces (output)'),
              items: [
                for (final i in outputs)
                  DropdownMenuItem(value: i.itemCode, child: Text(i.displayName)),
              ],
              onChanged: (v) => setState(() => _outputItemCode = v),
              validator: (v) => v == null ? 'Select the output item' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _outputPerPotCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Output per pot (kg)'),
              validator: (v) {
                final d = double.tryParse((v ?? '').trim());
                if (d == null || d <= 0) return 'Enter the kg produced per pot';
                return null;
              },
            ),
            const SizedBox(height: 20),
            Text('Inputs consumed per pot',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (var idx = 0; idx < _rows.length; idx++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _rows[idx].itemCode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Item',
                            isDense: true),
                        items: [
                          for (final i in inputCandidates)
                            DropdownMenuItem(
                                value: i.itemCode, child: Text(i.displayName)),
                        ],
                        onChanged: (v) =>
                            setState(() => _rows[idx].itemCode = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _rows[idx].qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Qty/pot',
                            isDense: true),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _rows.length == 1
                          ? null
                          : () => setState(() {
                                _rows[idx].qtyCtrl.dispose();
                                _rows.removeAt(idx);
                              }),
                    ),
                  ],
                ),
              ),
            TextButton.icon(
              onPressed: () => setState(() => _rows.add(_InputRow())),
              icon: const Icon(Icons.add),
              label: const Text('Add input'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Save recipe'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ],
        ),
      ),
    );
  }
}
