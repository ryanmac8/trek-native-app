import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../collab/collab_note.dart';
import '../../design/app_spacing.dart';
import '../../design/place_category_colors.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';

/// Per-trip shell: a bottom tab bar switching between the day/place/budget/
/// packing/todo/notes sections the issue #2 nav structure calls for. Notes
/// (issue #13) reads real data; the rest are still placeholders — none of
/// those data models exist yet (issues #4–#9).
class TripDashboardScreen extends StatefulWidget {
  const TripDashboardScreen({super.key, required this.tripId});

  final String tripId;

  @override
  State<TripDashboardScreen> createState() => _TripDashboardScreenState();
}

class _TripDashboardScreenState extends State<TripDashboardScreen> {
  int _tabIndex = 0;
  final _notesTabKey = GlobalKey<_NotesTabState>();

  static const _tabs = [
    (label: 'Days', icon: Icons.calendar_today),
    (label: 'Places', icon: Icons.place),
    (label: 'Budget', icon: Icons.attach_money),
    (label: 'Packing', icon: Icons.checklist),
    (label: 'Todos', icon: Icons.task_alt),
    (label: 'Notes', icon: Icons.sticky_note_2),
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
          const _ComingSoonTab(label: 'Todos'),
          _NotesTab(key: _notesTabKey, tripId: widget.tripId),
        ],
      ),
      floatingActionButton: _tabIndex == 5
          ? FloatingActionButton(
              onPressed: () => _notesTabKey.currentState?.createNote(),
              tooltip: 'New note',
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

/// The Notes tab: per docs/offline-first.md, the local cache
/// ([CollabRepository.cachedNotes]) is the source of truth for what's
/// shown — this paints from it immediately, then refreshes from the
/// network in the background. The FAB (owned by [TripDashboardScreen], via
/// [createNote]) opens a dialog for the note's title, content, and
/// category, then creates it optimistically — a note created while
/// offline stays queued and syncs on the next refresh, the same shape as
/// `TodoRepository.createItem`. Editing, pinning, file attachments, polls,
/// chat, and membership remain unbuilt for issue #13.
class _NotesTab extends ConsumerStatefulWidget {
  const _NotesTab({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<_NotesTab> createState() => _NotesTabState();
}

class _NotesTabState extends ConsumerState<_NotesTab> {
  List<CollabNote>? _notes;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(collabRepositoryProvider);
    final cached = await repository.cachedNotes(widget.tripId);
    if (!mounted) return;
    setState(() {
      _notes = cached;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = ref.read(collabRepositoryProvider);
    try {
      final refreshed = await repository.refreshNotes(widget.tripId);
      if (!mounted) return;
      setState(() {
        _notes = refreshed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Only surface an error state when there's nothing cached to show.
        if (_notes == null || _notes!.isEmpty) _error = e;
      });
    }
  }

  Future<void> createNote() async {
    final result = await showDialog<_NewCollabNote>(
      context: context,
      builder: (context) => const _CreateNoteDialog(),
    );
    if (result == null) return;

    try {
      final note = await ref
          .read(collabRepositoryProvider)
          .createNote(
            widget.tripId,
            title: result.title,
            content: result.content,
            category: result.category,
          );
      if (!mounted) return;
      setState(() => _notes = [...?_notes, note]);
      AppMessenger.showSuccess(
        note.isPending
            ? '"${note.title}" saved — will sync once you\'re back online.'
            : '"${note.title}" added.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cached = _notes;

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

    if (cached.isEmpty) {
      final error = _error;
      if (error is NetworkException) {
        return EmptyState(
          icon: Icons.cloud_off,
          message: "You're offline. Notes will load once you're back online.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      if (error != null) {
        return EmptyState(
          icon: Icons.error_outline,
          message: "Couldn't load notes.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      return const EmptyState(
        icon: Icons.sticky_note_2,
        message: 'No notes yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: cached.length,
        itemBuilder: (context, index) {
          final note = cached[index];
          return AppListRow(
            leading: note.pinned ? const Icon(Icons.push_pin) : null,
            title: note.title,
            subtitle: note.isPending
                ? 'Syncing…'
                : [
                    if (note.category != null) note.category!,
                    if (note.content != null && note.content!.isNotEmpty)
                      note.content!,
                  ].join(' · '),
            trailing: note.isPending ? const Icon(Icons.sync) : null,
          );
        },
      ),
    );
  }
}

class _NewCollabNote {
  const _NewCollabNote({required this.title, this.content, this.category});

  final String title;
  final String? content;
  final String? category;
}

class _CreateNoteDialog extends StatefulWidget {
  const _CreateNoteDialog();

  @override
  State<_CreateNoteDialog> createState() => _CreateNoteDialogState();
}

class _CreateNoteDialogState extends State<_CreateNoteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _categoryController = TextEditingController();

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New note'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'A title is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _contentController,
              decoration: const InputDecoration(
                labelText: 'Content (optional)',
              ),
              maxLines: 3,
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
            final content = _contentController.text.trim();
            final category = _categoryController.text.trim();
            Navigator.of(context).pop(
              _NewCollabNote(
                title: _titleController.text.trim(),
                content: content.isEmpty ? null : content,
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
