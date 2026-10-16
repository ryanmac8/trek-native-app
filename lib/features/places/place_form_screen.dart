import 'package:flutter/material.dart';

import '../../design/app_spacing.dart';
import '../../places/place.dart';
import 'category_avatar.dart';

/// What the user chose on a [PlaceFormScreen]: save [input], or delete the
/// place being edited. `null` from the route means they backed out.
class PlaceFormResult {
  const PlaceFormResult.save(PlaceInput this.input) : delete = false;
  const PlaceFormResult.delete() : input = null, delete = true;

  final PlaceInput? input;
  final bool delete;
}

/// Create/edit form for a place's own fields: name, description, address,
/// category, price + currency, and notes. Purely a form — it pops a [PlaceFormResult]
/// and leaves persisting it to the caller (`PlacesRepository`), so it works
/// the same offline.
///
/// Field limits mirror Trek's `PlacesController`: name 200, description
/// 2000, address 500, notes 2000 characters.
class PlaceFormScreen extends StatefulWidget {
  const PlaceFormScreen({super.key, this.place, this.categories = const []});

  /// The place being edited; `null` to create a new one.
  final Place? place;

  /// The server's categories (see `CategoriesRepository`), offered by the
  /// category picker. May be empty when none have been fetched yet.
  final List<PlaceCategoryRef> categories;

  @override
  State<PlaceFormScreen> createState() => _PlaceFormScreenState();
}

class _PlaceFormScreenState extends State<PlaceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.place?.name);
  late final _description = TextEditingController(
    text: widget.place?.description,
  );
  late final _address = TextEditingController(text: widget.place?.address);
  late final _price = TextEditingController(
    text: _formatPrice(widget.place?.price),
  );
  late final _currency = TextEditingController(text: widget.place?.currency);
  late final _notes = TextEditingController(text: widget.place?.notes);
  late int? _categoryId = widget.place?.category?.id;

  bool get _isEditing => widget.place != null;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _address,
      _price,
      _currency,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  static String _formatPrice(double? price) {
    if (price == null) return '';
    return price == price.roundToDouble()
        ? price.toStringAsFixed(0)
        : price.toString();
  }

  static double? _parsePrice(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final priceText = _price.text.trim();
    Navigator.of(context).pop(
      PlaceFormResult.save(
        PlaceInput(
          name: _name.text,
          description: _description.text,
          address: _address.text,
          categoryId: _categoryId,
          price: priceText.isEmpty ? null : _parsePrice(priceText),
          currency: _currency.text,
          notes: _notes.text,
        ),
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete place?'),
        content: Text(
          '"${widget.place!.name}" will be removed from this trip, '
          'including any days it is planned on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const PlaceFormResult.delete());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit place' : 'New place'),
        actions: [
          if (_isEditing)
            IconButton(
              tooltip: 'Delete place',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            TextFormField(
              controller: _name,
              autofocus: !_isEditing,
              decoration: const InputDecoration(labelText: 'Name'),
              maxLength: 200,
              textInputAction: TextInputAction.next,
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter a name.'
                  : null,
            ),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLength: 2000,
              minLines: 1,
              maxLines: 4,
            ),
            TextFormField(
              controller: _address,
              decoration: const InputDecoration(labelText: 'Address'),
              maxLength: 500,
              textInputAction: TextInputAction.next,
            ),
            _buildCategoryPicker(),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _price,
                    decoration: const InputDecoration(labelText: 'Price'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      final price = _parsePrice(text);
                      return price == null || price < 0
                          ? 'Enter a valid price.'
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _currency,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 3,
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (text.isEmpty) return null;
                      return RegExp(r'^[A-Za-z]{3}$').hasMatch(text)
                          ? null
                          : '3-letter code';
                    },
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _notes,
              decoration: const InputDecoration(labelText: 'Notes'),
              maxLength: 2000,
              minLines: 2,
              maxLines: 6,
            ),
          ],
        ),
      ),
    );
  }

  /// The server's categories, plus the place's current one if the list
  /// doesn't include it (e.g. nothing cached yet), so editing other fields
  /// never drops it.
  List<PlaceCategoryRef> get _categoryOptions {
    final current = widget.place?.category;
    if (current == null ||
        widget.categories.any((category) => category.id == current.id)) {
      return widget.categories;
    }
    return [...widget.categories, current];
  }

  Widget _buildCategoryPicker() {
    final options = _categoryOptions;
    return DropdownButtonFormField<int?>(
      initialValue: _categoryId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Category',
        helperText: widget.categories.isEmpty
            ? "Categories appear once they've loaded while online."
            : null,
      ),
      items: [
        const DropdownMenuItem<int?>(value: null, child: Text('No category')),
        for (final category in options)
          DropdownMenuItem<int?>(
            value: category.id,
            child: Row(
              children: [
                CategoryAvatar(category: category),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    category.name ?? 'Category ${category.id}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
      onChanged: (value) => setState(() => _categoryId = value),
    );
  }
}
