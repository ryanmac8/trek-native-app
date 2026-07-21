import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../config/server_config.dart';
import '../../design/app_spacing.dart';

/// First screen a fresh install lands on: Trek is self-hosted, so there is
/// no default server to point at (see docs/networking-auth.md). Collects
/// the public URL (required) and, optionally, a private/LAN URL plus the
/// Wi-Fi networks on which it should be used.
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _publicUrlController = TextEditingController();
  final _privateUrlController = TextEditingController();
  final _trustedNetworksController = TextEditingController();

  bool _isSaving = false;
  String? _errorMessage;

  @override
  void dispose() {
    _publicUrlController.dispose();
    _privateUrlController.dispose();
    _trustedNetworksController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final publicUrl = ServerConfig.validateUrl(_publicUrlController.text);
      final privateInput = _privateUrlController.text.trim();
      final privateUrl = privateInput.isEmpty
          ? null
          : ServerConfig.validateUrl(privateInput);
      final trustedWifiNetworks = _trustedNetworksController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();

      await ref
          .read(serverConfigStorageProvider)
          .write(
            ServerConfig(
              publicUrl: publicUrl,
              privateUrl: privateUrl,
              trustedWifiNetworks: trustedWifiNetworks,
            ),
          );

      if (mounted) context.go('/login');
    } on FormatException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect to your Trek server')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Trek is self-hosted — enter the address of your instance.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
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
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _privateUrlController,
                  decoration: const InputDecoration(
                    labelText: 'Private (LAN) server URL — optional',
                    hintText: 'http://192.168.1.50:3000',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _trustedNetworksController,
                  decoration: const InputDecoration(
                    labelText: 'Trusted Wi-Fi network names — optional',
                    hintText: 'Home Wi-Fi, Office',
                    helperText:
                        'Comma-separated. The private URL is used only on '
                        'these networks.',
                  ),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Continue'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
