import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../days/day.dart';
import '../../days/day_note.dart';
import '../../design/app_spacing.dart';
import '../../design/day_note_style.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../network/api_exception.dart';
import 'day_note_editor_sheet.dart';

/// One day of a trip's itinerary and its notes. Notes are added, edited, and
/// deleted through [DaysRepository], which applies each change to the local
/// cache first — so this works the same offline, with unsynced notes marked
/// until they reach the server.
class DayDetailScreen extends ConsumerStatefulWidget {
  const DayDetailScreen({super.key, required this.tripId, required this.day});

  final String tripId;

  /// The day as last shown in the Days tab — painted immediately, then
  /// replaced by the cache's copy.
  final Day day;

  @override
  ConsumerState<DayDetailScreen> createState() => _DayDetailScreenState();
}

class _DayDetailScreenState extends ConsumerState<DayDetailScreen> {
  late Day _day = widget.day;

  @override
  void initState() {
    super.initState();
    _reloadFromCache();
  }

  Future<void> _reloadFromCache() async {
    final days = await ref
        .read(daysRepositoryProvider)
        .cachedDays(widget.tripId);
    if (!mounted) return;
    for (final day in days) {
      if (day.id == widget.day.id) {
        setState(() => _day = day);
        return;
      }
    }
  }

  Future<void> _refresh() async {
    try {
      await ref.read(daysRepositoryProvider).refreshDays(widget.tripId);
    } on ApiException {
      // The cache is still shown; its notes stay marked as pending.
    }
    await _reloadFromCache();
  }

  Future<void> _addNote() async {
    final result = await showDayNoteEditor(context);
    if (result is! DayNoteSaved) return;
    await _write(
      () => ref
          .read(daysRepositoryProvider)
          .createDayNote(
            widget.tripId,
            dayId: _day.id,
            text: result.text,
            time: result.time,
            icon: result.icon,
            color: result.color,
          ),
    );
  }

  Future<void> _editNote(DayNote note) async {
    final result = await showDayNoteEditor(context, note: note);
    if (result == null) return;
    final repository = ref.read(daysRepositoryProvider);
    switch (result) {
      case DayNoteSaved():
        await _write(
          () => repository.updateDayNote(widget.tripId, note, {
            'text': result.text,
            'time': result.time,
            'icon': result.icon,
            'color': result.color,
          }),
        );
      case DayNoteDeleteRequested():
        await _write(() async {
          await repository.deleteDayNote(widget.tripId, note);
          return null;
        });
    }
  }

  /// Runs a note write and re-reads the cache it changed. A write that's
  /// only queued (offline) gets a heads-up; one the server refused gets an
  /// error, since the change has been undone.
  Future<void> _write(Future<DayNote?> Function() write) async {
    try {
      final note = await write();
      final pending =
          (note?.isPending ?? false) ||
          await ref
                  .read(daysRepositoryProvider)
                  .pendingNoteWriteCount(widget.tripId) >
              0;
      if (pending) {
        AppMessenger.showInfo(
          "Saved on this device — it'll sync when you're back online.",
        );
      }
    } on ApiException catch (e) {
      AppMessenger.showError("Couldn't save the note: ${e.message}");
    }
    await _reloadFromCache();
  }

  @override
  Widget build(BuildContext context) {
    final day = _day;
    final title = (day.title != null && day.title!.isNotEmpty)
        ? day.title!
        : 'Day ${day.dayNumber}';
    final date = day.date;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (date != null)
              Text(
                '${date.month}/${date.day}/${date.year}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNote,
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('Add note'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: day.noteItems.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: AppSpacing.xxl),
                  EmptyState(
                    icon: Icons.sticky_note_2_outlined,
                    message: 'No notes for this day yet.',
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xxl * 2,
                ),
                itemCount: day.noteItems.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.sm),
                itemBuilder: (context, index) {
                  final note = day.noteItems[index];
                  return _DayNoteCard(note: note, onTap: () => _editNote(note));
                },
              ),
      ),
    );
  }
}

class _DayNoteCard extends StatelessWidget {
  const _DayNoteCard({required this.note, required this.onTap});

  final DayNote note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final accent = DayNoteStyle.parse(note.color);
    final details = note.time;

    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor:
                accent?.withValues(alpha: 0.15) ??
                colorScheme.surfaceContainerHighest,
            child: DayNoteStyle.iconFor(
              note.icon,
              color: accent ?? colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.text, style: textTheme.titleSmall),
                if (details != null && details.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(details, style: textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          if (note.isPending)
            Tooltip(
              message: 'Not synced yet',
              child: Icon(
                Icons.cloud_upload_outlined,
                key: const Key('dayNotePending'),
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}
