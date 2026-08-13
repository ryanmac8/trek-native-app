import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/empty_state.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';
import '../../tags/tag.dart';

/// Preset swatches offered in the create-tag dialog. Trek's server falls
/// back to `#10b981` (the first swatch here) when no color is submitted, so
/// leaving the picker untouched matches the server default.
const _presetColors = [
  '#10b981',
  '#3b82f6',
  '#ef4444',
  '#f59e0b',
  '#8b5cf6',
  '#ec4899',
];

/// The `/tags` route: the user's tag list (issue #6's first slice — list +
/// create only). Per docs/offline-first.md, the local cache
/// ([TagsRepository.cachedTags]) is the source of truth for what's shown —
/// this paints from it immediately, then refreshes from the network in the
/// background. Applying/removing tags on a place and filtering the place
/// pool by tag are follow-ups, once this exists to filter against.
class TagsListScreen extends ConsumerStatefulWidget {
  const TagsListScreen({super.key});

  @override
  ConsumerState<TagsListScreen> createState() => _TagsListScreenState();
}

class _TagsListScreenState extends ConsumerState<TagsListScreen> {
  List<Tag>? _tags;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repository = ref.read(tagsRepositoryProvider);
    final cached = await repository.cachedTags();
    if (!mounted) return;
    setState(() {
      _tags = cached;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = ref.read(tagsRepositoryProvider);
    try {
      final refreshed = await repository.refreshTags();
      if (!mounted) return;
      setState(() {
        _tags = refreshed;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Only surface an error state when there's nothing cached to show.
        if (_tags == null || _tags!.isEmpty) _error = e;
      });
    }
  }

  Future<void> _createTag() async {
    final result = await showDialog<({String name, String? color})>(
      context: context,
      builder: (context) => const _CreateTagDialog(),
    );
    if (result == null) return;

    try {
      final tag = await ref
          .read(tagsRepositoryProvider)
          .createTag(name: result.name, color: result.color);
      if (!mounted) return;
      setState(() => _tags = [...?_tags, tag]);
      AppMessenger.showSuccess(
        tag.isPending
            ? '"${tag.name}" saved — will sync once you\'re back online.'
            : '"${tag.name}" created.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tags = _tags;

    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      floatingActionButton: FloatingActionButton(
        onPressed: _createTag,
        tooltip: 'New tag',
        child: const Icon(Icons.add),
      ),
      body: _buildBody(tags),
    );
  }

  Widget _buildBody(List<Tag>? tags) {
    if (tags == null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [
          SkeletonListTile(),
          SkeletonListTile(),
          SkeletonListTile(),
        ],
      );
    }

    if (tags.isEmpty) {
      final error = _error;
      if (error is NetworkException) {
        return EmptyState(
          icon: Icons.cloud_off,
          message: "You're offline. Tags will load once you're back online.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      if (error != null) {
        return EmptyState(
          icon: Icons.error_outline,
          message: "Couldn't load tags.",
          action: FilledButton(onPressed: _refresh, child: const Text('Retry')),
        );
      }
      return const EmptyState(
        icon: Icons.label_outline,
        message: 'No tags yet.',
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.md),
        itemCount: tags.length,
        itemBuilder: (context, index) {
          final tag = tags[index];
          return AppListRow(
            leading: _TagSwatch(color: tag.color),
            title: tag.name,
            subtitle: tag.isPending ? 'Syncing…' : null,
            trailing: tag.isPending ? const Icon(Icons.sync) : null,
          );
        },
      ),
    );
  }
}

class _TagSwatch extends StatelessWidget {
  const _TagSwatch({required this.color});

  final String? color;

  @override
  Widget build(BuildContext context) {
    final parsed = _parseColor(color) ?? Theme.of(context).colorScheme.primary;
    return CircleAvatar(backgroundColor: parsed, radius: 12);
  }

  /// Parses a `#rrggbb` hex string (Trek's tag color format) into a
  /// [Color]; `null` if it doesn't match.
  static Color? _parseColor(String? hex) {
    if (hex == null) return null;
    final normalized = hex.replaceFirst('#', '');
    if (normalized.length != 6) return null;
    final value = int.tryParse(normalized, radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }
}

class _CreateTagDialog extends StatefulWidget {
  const _CreateTagDialog();

  @override
  State<_CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<_CreateTagDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _selectedColor = _presetColors.first;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New tag'),
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
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final hex in _presetColors)
                  _ColorSwatchOption(
                    hex: hex,
                    selected: hex == _selectedColor,
                    onTap: () => setState(() => _selectedColor = hex),
                  ),
              ],
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
            Navigator.of(
              context,
            ).pop((name: _nameController.text.trim(), color: _selectedColor));
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _ColorSwatchOption extends StatelessWidget {
  const _ColorSwatchOption({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final normalized = hex.replaceFirst('#', '');
    final value = int.parse(normalized, radix: 16);
    final color = Color(0xFF000000 | value);
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: CircleAvatar(
        backgroundColor: color,
        radius: 16,
        child: selected
            ? const Icon(Icons.check, color: Colors.white, size: 16)
            : null,
      ),
    );
  }
}
