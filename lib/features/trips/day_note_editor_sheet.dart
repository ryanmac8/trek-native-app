import 'package:flutter/material.dart';

import '../../days/day_note.dart';
import '../../design/app_spacing.dart';
import '../../design/day_note_style.dart';

/// What the editor sheet hands back: the note's new content, or a request
/// to delete it.
sealed class DayNoteEditorResult {
  const DayNoteEditorResult();
}

class DayNoteSaved extends DayNoteEditorResult {
  const DayNoteSaved({
    required this.text,
    this.time,
    required this.icon,
    this.color,
  });

  final String text;
  final String? time;
  final String icon;
  final String? color;
}

class DayNoteDeleteRequested extends DayNoteEditorResult {
  const DayNoteDeleteRequested();
}

/// Opens the add/edit sheet for a day note. Pass [note] to edit (which also
/// offers delete, behind a confirmation); omit it to add. Resolves to `null`
/// if dismissed.
Future<DayNoteEditorResult?> showDayNoteEditor(
  BuildContext context, {
  DayNote? note,
}) {
  return showModalBottomSheet<DayNoteEditorResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _DayNoteEditor(note: note),
  );
}

class _DayNoteEditor extends StatefulWidget {
  const _DayNoteEditor({this.note});

  final DayNote? note;

  @override
  State<_DayNoteEditor> createState() => _DayNoteEditorState();
}

class _DayNoteEditorState extends State<_DayNoteEditor> {
  /// The server's per-field limits (`dayNoteCreateRequestSchema`).
  static const _textMax = 500;
  static const _timeMax = 2000;

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _text;
  late final TextEditingController _time;
  late String _icon;
  String? _color;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _text = TextEditingController(text: note?.text ?? '');
    _time = TextEditingController(text: note?.time ?? '');
    _icon = note?.icon ?? DayNote.defaultIcon;
    _color = DayNoteStyle.parse(note?.color) == null ? null : note!.color;
  }

  @override
  void dispose() {
    _text.dispose();
    _time.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final time = _time.text.trim();
    Navigator.of(context).pop(
      DayNoteSaved(
        text: _text.text.trim(),
        time: time.isEmpty ? null : _time.text,
        icon: _icon,
        color: _color,
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete note?'),
        content: const Text('This removes the note for everyone on the trip.'),
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
      Navigator.of(context).pop(const DayNoteDeleteRequested());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.note != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEditing ? 'Edit note' : 'Add note',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const Key('dayNoteText'),
                controller: _text,
                autofocus: !isEditing,
                maxLength: _textMax,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Enter a title for the note.'
                    : null,
              ),
              TextFormField(
                key: const Key('dayNoteTime'),
                controller: _time,
                maxLength: _timeMax,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Details (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text('Icon', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final entry in DayNoteStyle.icons.entries)
                    IconButton(
                      key: Key('dayNoteIcon-${entry.key}'),
                      tooltip: entry.key,
                      isSelected: _icon == entry.key,
                      style: IconButton.styleFrom(
                        backgroundColor: _icon == entry.key
                            ? colorScheme.primaryContainer
                            : null,
                      ),
                      onPressed: () => setState(() => _icon = entry.key),
                      icon: Icon(entry.value),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text('Color', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _ColorSwatch(
                    key: const Key('dayNoteColor-none'),
                    color: null,
                    selected: _color == null,
                    onTap: () => setState(() => _color = null),
                  ),
                  for (final color in DayNoteStyle.colors)
                    _ColorSwatch(
                      key: Key('dayNoteColor-${DayNoteStyle.hex(color)}'),
                      color: color,
                      selected: _color == DayNoteStyle.hex(color),
                      onTap: () =>
                          setState(() => _color = DayNoteStyle.hex(color)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  if (isEditing)
                    TextButton.icon(
                      onPressed: _confirmDelete,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.error,
                      ),
                    ),
                  const Spacer(),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    super.key,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: color == null ? 'No color' : DayNoteStyle.hex(color!),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color ?? colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: selected ? colorScheme.onSurface : colorScheme.outline,
              width: selected ? 3 : 1,
            ),
          ),
          child: color == null
              ? Icon(Icons.block, size: 16, color: colorScheme.outline)
              : null,
        ),
      ),
    );
  }
}
