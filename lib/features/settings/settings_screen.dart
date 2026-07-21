import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_list_row.dart';

/// Settings hub — a list of sub-pages, matching the pattern self-hosted
/// apps like Immich use rather than one long flat form. Only "Networking"
/// exists so far; more rows (account, appearance, etc.) belong here as
/// they're built, not guessed at now. Logout lives in this AppBar rather
/// than the trip list's — it's an account-level action, not a trip one.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () async {
              await ref.read(authServiceProvider).logout();
              AppMessenger.showInfo('Logged out.');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        children: [
          AppListRow(
            leading: const Icon(Icons.wifi),
            title: 'Networking',
            subtitle: 'Server address, local network',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/networking'),
          ),
        ],
      ),
    );
  }
}
