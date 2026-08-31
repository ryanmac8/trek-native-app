import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/account_models.dart';
import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../config/server_config.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_card.dart';
import '../../design/widgets/skeleton_box.dart';
import '../../network/api_exception.dart';

/// Settings & account management (first slice of issue #27).
///
/// Per docs/offline-first.md the account section reads through
/// [AccountRepository]: the last-known profile paints from the local cache
/// first, and a failed refresh falls back to that cache with an offline
/// notice rather than blanking or throwing. When nothing is cached and the
/// device is offline, an explicit offline state with a retry is shown.
///
/// This slice is read-only account info plus server management and sign
/// out. Editing the profile, changing the password, managing MFA, and
/// deleting the account are mutations deferred to a follow-up slice (a
/// password change re-issues the session, which needs its own re-auth
/// flow on a bearer client).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  TrekAccount? _account;
  ServerConfig? _serverConfig;
  Object? _error;
  bool _fromCache = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final repository = ref.read(accountRepositoryProvider);

    // The server config is a purely local read — show it regardless of
    // connectivity.
    final serverConfig = await ref.read(serverConfigStorageProvider).read();
    if (mounted) setState(() => _serverConfig = serverConfig);

    // Paint the cached profile first so the screen isn't blank while the
    // refresh runs.
    final cached = await repository.cachedAccount();
    if (mounted && cached != null) {
      setState(() {
        _account = cached;
        _fromCache = true;
      });
    }

    try {
      final account = await repository.refreshAccount();
      if (!mounted) return;
      setState(() {
        _account = account;
        _fromCache = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Keep showing the cached profile (marked stale) if we have one;
        // otherwise surface the failure so the screen can offer a retry.
        if (_account == null) {
          _error = e;
        } else {
          _fromCache = true;
        }
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    await ref.read(accountRepositoryProvider).clearCachedAccount();
    await ref.read(authServiceProvider).logout();
    AppMessenger.showInfo('Signed out.');
  }

  Future<void> _changeServer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change server?'),
        content: const Text(
          'This signs you out and returns to server setup. Your trips stay '
          'on the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Change server'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(accountRepositoryProvider).clearCachedAccount();
    await ref.read(serverConfigStorageProvider).clear();
    await ref.read(authServiceProvider).logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            _SectionHeader('Account'),
            const SizedBox(height: AppSpacing.sm),
            _buildAccount(context),
            const SizedBox(height: AppSpacing.lg),
            _SectionHeader('Server'),
            const SizedBox(height: AppSpacing.sm),
            _ServerCard(config: _serverConfig, onChange: _changeServer),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton.icon(
              onPressed: _signOut,
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccount(BuildContext context) {
    final account = _account;

    if (account == null && _loading) {
      return const AppCard(
        child: Row(
          children: [
            SkeletonBox(width: 48, height: 48),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 140, height: 16),
                  SizedBox(height: AppSpacing.sm),
                  SkeletonBox(width: 200, height: 12),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (account == null) {
      final offline = _error is NetworkException;
      return AppCard(
        child: Column(
          children: [
            Icon(
              offline ? Icons.cloud_off : Icons.error_outline,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              offline
                  ? "You're offline, and this account hasn't been loaded yet."
                  : "Couldn't load your account.",
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return _AccountCard(account: account, fromCache: _fromCache);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.fromCache});

  final TrekAccount account;
  final bool fromCache;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final initial = account.username.isNotEmpty
        ? account.username[0].toUpperCase()
        : (account.email.isNotEmpty ? account.email[0].toUpperCase() : '?');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(radius: 24, child: Text(initial)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(account.username, style: textTheme.titleMedium),
                    Text(
                      account.email,
                      style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (account.role == 'admin')
                const _Tag(icon: Icons.shield_outlined, label: 'Admin'),
              _Tag(
                icon: account.mfaEnabled ? Icons.lock : Icons.lock_open,
                label: account.mfaEnabled ? 'MFA on' : 'MFA off',
              ),
              if (account.isSsoAccount)
                const _Tag(icon: Icons.badge_outlined, label: 'SSO account'),
            ],
          ),
          if (account.createdAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Member since ${_formatDate(account.createdAt!)}',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (fromCache) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.cloud_off,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Showing saved details — you may be offline.',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
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
    final local = date.toLocal();
    return '${months[local.month - 1]} ${local.year}';
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({required this.config, required this.onChange});

  final ServerConfig? config;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final config = this.config;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (config == null)
            Text('No server configured.', style: textTheme.bodyMedium)
          else ...[
            _Field(label: 'Public URL', value: config.publicUrl),
            if (config.privateUrl != null) ...[
              const SizedBox(height: AppSpacing.sm),
              _Field(label: 'Private URL', value: config.privateUrl!),
            ],
            if (config.trustedWifiNetworks.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              _Field(
                label: 'Trusted Wi-Fi',
                value: config.trustedWifiNetworks.join(', '),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            'The private URL is used only on a trusted Wi-Fi network.',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onChange,
              icon: const Icon(Icons.dns_outlined),
              label: const Text('Change server'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(value, style: textTheme.bodyMedium),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
