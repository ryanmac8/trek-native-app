import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/place_category_colors.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../todos/todo_item.dart';

/// Per-trip shell: a bottom tab bar switching between the day/place/budget/
/// packing/todo sections the issue #2 nav structure calls for. Todos
/// (issue #9) reads real data; the rest are still placeholders — none of
/// those data models exist yet (issues #4–#8).
class TripDashboardScreen extends StatefulWidget {
  const TripDashboardScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<TripDashboardScreen> createState() => _TripDashboardScreenState();
}

class _TripDashboardScreenState extends State<TripDashboardScreen> {
  int _tabIndex = 0;
  final _todosTabKey = GlobalKey<_TodosTabState>();

  static const _tabs = [
    (label: 'Days', icon: Icons.calendar_today),
    (label: 'Places', icon: Icons.place),
    (label: 'Budget', icon: Icons.attach_money),
    (label: 'Packing', icon: Icons.checklist),
    (label: 'Todos', icon: Icons.task_alt),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Trip ${widget.tripId}')),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          const _ComingSoonTab(label: 'Days'),
          const _PlacesPreviewTab(),
          const _ComingSoonTab(label: 'Budget'),
          const _ComingSoonTab(label: 'Packing'),
          _TodosTab(key: _todosTabKey, tripId: widget.tripId),
        ],
      ),
      floatingActionButton: _tabIndex == 4
          ? FloatingActionButton(
              onPressed: () => _todosTabKey.currentState?.createItem(),
              tooltip: 'New todo',
              child: const Icon(Icons.add),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (index) => setState(() => _tabIndex = index),
        destinations: [
          for (final tab in _tabs)
            NavigationDestination(icon: Icon(tab.icon), label: tab.label),
        ],
      ),
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  const _ComingSoonTab({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        '$label — coming soon',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}

/// The Places tab has no data yet, but doubles as a visual check of the
/// category color/icon tokens ([PlaceCategory]) against Trek's real
/// category list.
class _PlacesPreviewTab extends StatelessWidget {
  const _PlacesPreviewTab();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        Text(
          'Places — coming soon',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final category in PlaceCategory.values)
              Chip(
                avatar: CircleAvatar(
                  backgroundColor: category.color,
                  child: Text(
                    category.icon,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                label: Text(category.label),
              ),
          ],
        ),
      ],
    );
  }
}

/// The Todos tab: per docs/offline-first.md, the local cache
/// ([TodoRepository.cachedItems]) is the source of truth for what's shown —
/// this paints from it immediately, then refreshes from the network in the
/// background. The FAB (owned by [TripDashboardScreen], via [createItem])
/// opens a dialog for the item's name and category, then creates it
/// optimistically — an item created while offline stays queued and syncs on
/// the next refresh, the same shape as `PackingRepository.createItem`.
/// Tapping a synced row toggles it checked/unchecked the same way
/// ([TodoRepository.toggleChecked]); a still-pending (unsynced) row isn't
/// tappable. Swiping a row deletes it, after confirmation
/// ([TodoRepository.deleteItem]) — a delete made while offline stays queued
/// and the row stays hidden. Reorder, due dates, description, assignment,
/// and priority remain unbuilt for issue #9.
class _TodosTab extends ConsumerStatefulWidget {
  const _TodosTab({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<_TodosTab> createState() => _TodosTabState();
}

class _TodosTabState extends ConsumerState<_TodosTab> {
  List<TodoItem>? _items;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(todoRepositoryProvider);
    final cached = await repository.cachedItems(widget.tripId);
    if (!mounted) return;
    setState(() {
      _items = cached;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = ref.read(todoRepositoryProvider);
    try {
      final refreshed = await repository.refreshItems(widget.tripId);
      if (!mounted) return;
      setState(() {
        _items = refreshed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Only surface an error state when there's nothing cached to show.
        if (_items == null || _items!.isEmpty) _error = e;
      });
    }
  }

  Future<void> _toggleChecked(TodoItem item) async {
    try {
      final updated = await ref
          .read(todoRepositoryProvider)
          .toggleChecked(widget.tripId, item);
      if (!mounted) return;
      setState(() {
        _items = [
          for (final existing in _items ?? const <TodoItem>[])
            if (existing.localId == item.localId) updated else existing,
        ];
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(e.message);
    }
  }

  Future<bool> _confirmDelete(TodoItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete todo?'),
        content: Text('"${item.name}" will be removed.'),
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
    return confirmed ?? false;
  }

  Future<void> _reorderItems(int oldIndex, int newIndex) async {
    final current = _items ?? const <TodoItem>[];
    final visible = current.where((item) => !item.pendingDelete).toList();
    // Tombstones (still-queued offline deletes) are hidden from the visible
    // list `oldIndex`/`newIndex` index into, so they aren't part of the
    // reorder — keep them appended, out of the way, until they sync away.
    final tombstones = current.where((item) => item.pendingDelete).toList();

    if (newIndex > oldIndex) newIndex -= 1;
    final moved = visible.removeAt(oldIndex);
    visible.insert(newIndex, moved);
    final newOrder = [...visible, ...tombstones];

    setState(() => _items = newOrder);

    try {
      await ref
          .read(todoRepositoryProvider)
          .reorderItems(widget.tripId, newOrder);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _items = current);
      AppMessenger.showError(e.message);
    }
  }

  Future<void> _deleteItem(TodoItem item) async {
    setState(() {
      _items = [
        for (final existing in _items ?? const <TodoItem>[])
          if (existing.localId != item.localId) existing,
      ];
    });

    try {
      await ref.read(todoRepositoryProvider).deleteItem(widget.tripId, item);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _items = [...?_items, item]);
      AppMessenger.showError(e.message);
    }
  }

  Future<void> createItem() async {
    final result = await showDialog<_NewTodoItem>(
      context: context,
      builder: (context) => const _CreateTodoItemDialog(),
    );
    if (result == null) return;

    try {
      final item = await ref
          .read(todoRepositoryProvider)
          .createItem(
            widget.tripId,
            name: result.name,
            category: result.category,
          );
      if (!mounted) return;
      setState(() => _items = [...?_items, item]);
      AppMessenger.showSuccess(
        item.isPending
            ? '"${item.name}" saved — will sync once you\'re back online.'
            : '"${item.name}" added.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cached = _items;

    if (cached == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonListTile(),
          SkeletonListTile(),
          SkeletonListTile(),
        ],
      );
    }

    // A still-queued (offline) delete is hidden here but kept in the cache
    // as a tombstone so the next refresh can retry it — see
    // TodoRepository.deleteItem.
    final items = cached.where((item) => !item.pendingDelete).toList();

    if (items.isEmpty) {
      final error = _error;
      if (error is NetworkException) {
        return EmptyState(
          icon: Icons.cloud_off,
          message: "You're offline. Todos will load once you're back online.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      if (error != null) {
        return EmptyState(
          icon: Icons.error_outline,
          message: "Couldn't load todos.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      return const EmptyState(icon: Icons.task_alt, message: 'No todos yet.');
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        buildDefaultDragHandles: false,
        itemCount: items.length,
        // ignore: deprecated_member_use
        onReorder: _reorderItems,
        itemBuilder: (context, index) {
          final item = items[index];
          return Dismissible(
            key: ValueKey(item.localId),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              color: Theme.of(context).colorScheme.errorContainer,
              child: Icon(
                Icons.delete,
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
            confirmDismiss: (_) => _confirmDelete(item),
            onDismissed: (_) => _deleteItem(item),
            child: AppListRow(
              leading: ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_handle),
              ),
              title: item.name,
              subtitle: item.isPending ? 'Syncing…' : item.category,
              trailing: Icon(
                item.isPending
                    ? Icons.sync
                    : item.checked
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
              ),
              onTap: item.isPending ? null : () => _toggleChecked(item),
            ),
          );
        },
      ),
    );
  }
}

class _NewTodoItem {
  const _NewTodoItem({required this.name, this.category});

  final String name;
  final String? category;
}

class _CreateTodoItemDialog extends StatefulWidget {
  const _CreateTodoItemDialog();

  @override
  State<_CreateTodoItemDialog> createState() => _CreateTodoItemDialogState();
}

class _CreateTodoItemDialogState extends State<_CreateTodoItemDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New todo'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'A name is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _categoryController,
              decoration: const InputDecoration(
                labelText: 'Category (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            final category = _categoryController.text.trim();
            Navigator.of(context).pop(
              _NewTodoItem(
                name: _nameController.text.trim(),
                category: category.isEmpty ? null : category,
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}
