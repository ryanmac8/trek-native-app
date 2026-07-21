import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../config/server_config.dart';
import '../../design/app_spacing.dart';
import '../../design/widgets/app_list_row.dart';
import '../../design/widgets/loading_indicator.dart';

/// Edits the full `ServerConfig` — including the public URL entered during
/// first-run setup (`ServerSetupScreen`), which only asks for that one
/// field to get onboarding to login as fast as possible. Private (LAN)
/// endpoints are power-user settings that belong here instead, reached from
/// `SettingsScreen`'s list rather than asked for up front.
class NetworkingSettingsScreen extends ConsumerStatefulWidget {
  const NetworkingSettingsScreen({super.key});

  @override
  ConsumerState<NetworkingSettingsScreen> createState() =>
      _NetworkingSettingsScreenState();
}

class _NetworkingSettingsScreenState
    extends ConsumerState<NetworkingSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _publicUrlController = TextEditingController();

  List<PrivateEndpoint> _privateEndpoints = [];

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await ref.read(serverConfigStorageProvider).read();
    if (!mounted) return;
    setState(() {
      _publicUrlController.text = config?.publicUrl ?? '';
      _privateEndpoints = List.of(config?.privateEndpoints ?? const []);
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    _publicUrlController.dispose();
    super.dispose();
  }

  Future<void> _addEndpoint() async {
    final endpoint = await showDialog<PrivateEndpoint>(
      context: context,
      builder: (_) => const _AddEndpointDialog(),
    );
    if (endpoint != null) {
      setState(() => _privateEndpoints.add(endpoint));
    }
  }

  void _removeEndpoint(int index) {
    setState(() => _privateEndpoints.removeAt(index));
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final publicUrl = ServerConfig.validateUrl(_publicUrlController.text);

      await ref
          .read(serverConfigStorageProvider)
          .write(
            ServerConfig(
              publicUrl: publicUrl,
              privateEndpoints: _privateEndpoints,
            ),
          );

      if (mounted) {
        AppMessenger.showSuccess('Networking settings saved.');
        context.pop();
      }
    } on FormatException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Networking')),
      body: SafeArea(
        child: _isLoading
            ? const LoadingIndicator()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _publicUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Public server URL',
                          hintText: 'https://trek.example.com',
                        ),
                        keyboardType: TextInputType.url,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'A public server URL is required.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Private (LAN) endpoints',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'On a home or office network with a faster local '
                        "address for your server? Add it below — it's used "
                        "automatically whenever you're on that endpoint's "
                        'Wi-Fi network.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_privateEndpoints.isEmpty)
                        Text(
                          'No private endpoints added.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        )
                      else
                        for (final entry in _privateEndpoints.asMap().entries)
                          AppListRow(
                            title: entry.value.wifiNetwork,
                            subtitle: entry.value.url,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove endpoint',
                              onPressed: () => _removeEndpoint(entry.key),
                            ),
                          ),
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _addEndpoint,
                        icon: const Icon(Icons.add),
                        label: const Text('Add endpoint'),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton(
                        onPressed: _isSaving ? null : _save,
                        child: _isSaving
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save'),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Collects a URL + associated Wi-Fi network name for a new [PrivateEndpoint],
/// pinging the URL's `/api/health` before returning it so a typo'd address
/// doesn't get saved silently. Reachability is advisory, not a hard gate —
/// per docs/offline-first.md, the LAN address might legitimately be
/// unreachable right now (e.g. added while away from home) but still worth
/// saving for later.
class _AddEndpointDialog extends ConsumerStatefulWidget {
  const _AddEndpointDialog();

  @override
  ConsumerState<_AddEndpointDialog> createState() => _AddEndpointDialogState();
}

class _AddEndpointDialogState extends ConsumerState<_AddEndpointDialog> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _wifiController = TextEditingController();

  bool _isChecking = false;
  bool _unreachable = false;
  String? _errorMessage;

  @override
  void dispose() {
    _urlController.dispose();
    _wifiController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentWifi() async {
    final ssid = await ref.read(wifiNetworkInfoProvider).currentSsid();
    if (!mounted) return;
    if (ssid == null) {
      AppMessenger.showError("Not connected to a Wi-Fi network right now.");
      return;
    }
    setState(() => _wifiController.text = ssid);
  }

  Future<void> _save({required bool skipCheck}) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final String url;
    try {
      url = ServerConfig.validateUrl(_urlController.text);
    } on FormatException catch (e) {
      setState(() => _errorMessage = e.message);
      return;
    }
    final wifiNetwork = _wifiController.text.trim();

    if (skipCheck) {
      if (mounted) {
        Navigator.of(
          context,
        ).pop(PrivateEndpoint(url: url, wifiNetwork: wifiNetwork));
      }
      return;
    }

    setState(() {
      _isChecking = true;
      _unreachable = false;
      _errorMessage = null;
    });

    final reachable = await ref.read(serverHealthCheckProvider).ping(url);

    if (!mounted) return;
    if (reachable) {
      Navigator.of(
        context,
      ).pop(PrivateEndpoint(url: url, wifiNetwork: wifiNetwork));
    } else {
      setState(() {
        _isChecking = false;
        _unreachable = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add endpoint'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Private (LAN) URL',
                hintText: 'http://192.168.1.50:3000',
              ),
              keyboardType: TextInputType.url,
              autofocus: true,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'A URL is required.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _wifiController,
              decoration: const InputDecoration(
                labelText: 'Wi-Fi network name',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'A Wi-Fi network name is required.';
                }
                return null;
              },
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _useCurrentWifi,
                child: const Text('Use current Wi-Fi network'),
              ),
            ),
            if (_unreachable)
              Text(
                "Couldn't reach this address from here.",
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            else if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isChecking ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (_unreachable)
          TextButton(
            onPressed: _isChecking ? null : () => _save(skipCheck: false),
            child: const Text('Try again'),
          ),
        FilledButton(
          onPressed: _isChecking ? null : () => _save(skipCheck: _unreachable),
          child: _isChecking
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(_unreachable ? 'Save anyway' : 'Save'),
        ),
      ],
    );
  }
}
