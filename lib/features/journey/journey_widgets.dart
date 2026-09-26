import 'package:flutter/material.dart';

import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/empty_state.dart';
import '../../network/api_exception.dart';

/// Whether [error] is the Journey addon gate's answer: every
/// `/api/journeys` route returns `404 { error: 'Journey addon is not
/// enabled' }` while the addon is off on the server.
bool isJourneyAddonDisabled(Object? error) =>
    error is ServerException &&
    error.statusCode == 404 &&
    error.message.toLowerCase().contains('addon');

/// The "nothing to show" state for a failed load with nothing cached:
/// offline, addon disabled, not found, or a generic error — each with a
/// Retry except the addon case, which only a server admin can fix.
class JourneyLoadError extends StatelessWidget {
  const JourneyLoadError({
    super.key,
    required this.error,
    required this.what,
    required this.onRetry,
  });

  final Object? error;

  /// What failed to load, e.g. "your journeys".
  final String what;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = FilledButton(onPressed: onRetry, child: const Text('Retry'));
    final error = this.error;
    if (isJourneyAddonDisabled(error)) {
      return const EmptyState(
        icon: Icons.extension_off,
        message: "The Journey addon isn't enabled on this server.",
      );
    }
    if (error is NetworkException) {
      return EmptyState(
        icon: Icons.cloud_off,
        message: "You're offline, and there's no saved copy of $what yet.",
        action: retry,
      );
    }
    if (error is ServerException && error.statusCode == 404) {
      return const EmptyState(
        icon: Icons.search_off,
        message: 'This journey no longer exists or was unshared.',
      );
    }
    return EmptyState(
      icon: Icons.error_outline,
      message: "Couldn't load $what.",
      action: retry,
    );
  }
}

/// "Offline — showing … from <time>" with a Retry, above a stale snapshot.
class JourneyStaleBanner extends StatelessWidget {
  const JourneyStaleBanner({
    super.key,
    required this.what,
    required this.fetchedAt,
    required this.onRetry,
  });

  final String what;
  final DateTime fetchedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final local = fetchedAt.toLocal();
    final date =
        '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.cloud_off, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('Offline — showing $what from $date.')),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

/// Makes a non-scrolling state (e.g. [EmptyState]) fill the viewport while
/// still supporting pull-to-refresh.
class FillScrollable extends StatelessWidget {
  const FillScrollable({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(height: constraints.maxHeight, child: child),
      ),
    );
  }
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `2026-03-14` → `Mar 14, 2026`; anything unparseable is returned as-is.
String formatJourneyDate(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  return '${_months[date.month - 1]} ${date.day}, ${date.year}';
}

/// A `start – end` label from two optional `YYYY-MM-DD` dates, or `null`
/// if neither is set.
String? formatJourneyDateRange(String? start, String? end) {
  if (start == null && end == null) return null;
  if (start == null || end == null || start == end) {
    return formatJourneyDate((start ?? end)!);
  }
  return '${formatJourneyDate(start)} – ${formatJourneyDate(end)}';
}

String _two(int n) => n.toString().padLeft(2, '0');
