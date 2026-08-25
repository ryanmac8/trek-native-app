import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/loading_indicator.dart';
import '../../network/api_exception.dart';
import '../../share/share_link.dart';

/// Lets a trip's owner/editor turn on a public, read-only share link (first
/// slice of issue #14) and choose which sections a visitor with the link
/// can see. Per docs/offline-first.md, the local cache
/// (`ShareRepository.cachedShareLink`) is the source of truth for what's
/// shown — this paints from it immediately, then refreshes from the network
/// in the background. Enabling, updating, or disabling sharing applies
/// optimistically; a change made while offline stays queued and syncs on
/// the next refresh, the same shape as `BudgetRepository.createItem`.
/// Export (PDF/ICS, etc.) is not part of this first slice of issue #14.
class ShareScreen extends ConsumerStatefulWidget {
  const ShareScreen({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends ConsumerState<ShareScreen> {
  bool _loaded = false;
  ShareLink? _link;
  Object? _error;
  bool _busy = false;

  // Map & itinerary has no toggle below — mirrors Trek's web client
  // (`TripMembersModal.tsx`'s `share_map` permission is marked `always:
  // true`), which never lets it be turned off once sharing is on.
  bool _shareBookings = true;
  bool _sharePacking = false;
  bool _shareBudget = false;
  bool _shareCollab = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _applyToggles(ShareLink? link) {
    _shareBookings = link?.shareBookings ?? true;
    _sharePacking = link?.sharePacking ?? false;
    _shareBudget = link?.shareBudget ?? false;
    _shareCollab = link?.shareCollab ?? false;
  }

  Future<void> _load() async {
    final repository = ref.read(shareRepositoryProvider);
    final cached = await repository.cachedShareLink(widget.tripId);
    if (!mounted) return;
    setState(() {
      _link = cached;
      _applyToggles(cached);
      _loaded = true;
      _error = null;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final repository = ref.read(shareRepositoryProvider);
    try {
      final refreshed = await repository.refreshShareLink(widget.tripId);
      if (!mounted) return;
      setState(() {
        _link = refreshed;
        // A save/disable already in flight owns the toggle values until it
        // resolves — don't let a background refresh clobber it.
        if (refreshed == null || !refreshed.needsSync) {
          _applyToggles(refreshed);
        }
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      // Only surface an error state when there's nothing cached to show.
      setState(() {
        if (_link == null) _error = e;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final link = await ref
          .read(shareRepositoryProvider)
          .setSharing(
            widget.tripId,
            shareBookings: _shareBookings,
            sharePacking: _sharePacking,
            shareBudget: _shareBudget,
            shareCollab: _shareCollab,
          );
      if (!mounted) return;
      setState(() => _link = link);
      AppMessenger.showSuccess(
        link.needsSync
            ? 'Saved — will sync once you\'re back online.'
            : 'Sharing settings saved.',
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stopSharing() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Stop sharing?'),
        content: const Text(
          'Anyone with the link will lose access to this trip.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop sharing'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(shareRepositoryProvider).disableSharing(widget.tripId);
      if (!mounted) return;
      setState(() {
        _link = null;
        _applyToggles(null);
      });
      AppMessenger.showSuccess('Sharing turned off.');
    } on ApiException catch (e) {
      if (!mounted) return;
      AppMessenger.showError(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyLink() async {
    final token = _link?.token;
    if (token == null) return;
    // Deliberately the configured *public* URL, not the Wi-Fi-aware
    // resolver `ApiClient` uses — a share link handed to someone else must
    // resolve for them, not for whichever URL this device would currently
    // reach the server on.
    final serverConfig = await ref.read(serverConfigStorageProvider).read();
    final baseUrl = serverConfig?.publicUrl;
    if (baseUrl == null) return;
    await Clipboard.setData(ClipboardData(text: '$baseUrl/shared/$token'));
    if (!mounted) return;
    AppMessenger.showSuccess('Link copied.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share trip')),
      body: _loaded ? _buildBody(context) : const LoadingIndicator(),
    );
  }

  Widget _buildBody(BuildContext context) {
    final link = _link;
    final enabled = link?.isEnabled ?? false;
    final syncing = link?.needsSync == true || link?.pendingDelete == true;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (_error is NetworkException)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: Text(
                  "You're offline. Sharing status may be out of date.",
                ),
              ),
            ),
          ),
        Row(
          children: [
            Icon(
              enabled ? Icons.public : Icons.public_off,
              color: enabled
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                enabled ? 'Sharing is on' : 'Sharing is off',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (syncing) const Icon(Icons.sync),
          ],
        ),
        if (enabled && link?.token != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  link!.token!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy link',
                onPressed: _copyLink,
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Visible to anyone with the link',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.check_circle_outline),
          title: Text('Map & itinerary'),
          subtitle: Text('Always included once sharing is on'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bookings'),
          subtitle: const Text('Accommodations and reservations'),
          value: _shareBookings,
          onChanged: _busy
              ? null
              : (value) => setState(() => _shareBookings = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Packing list'),
          subtitle: const Text('Shared (non-private) items only'),
          value: _sharePacking,
          onChanged: _busy
              ? null
              : (value) => setState(() => _sharePacking = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Budget'),
          value: _shareBudget,
          onChanged: _busy
              ? null
              : (value) => setState(() => _shareBudget = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Collab chat'),
          value: _shareCollab,
          onChanged: _busy
              ? null
              : (value) => setState(() => _shareCollab = value),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(enabled ? 'Save changes' : 'Enable sharing'),
        ),
        if (enabled) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton(
            onPressed: _busy ? null : _stopSharing,
            child: const Text('Stop sharing'),
          ),
        ],
      ],
    );
  }
}
