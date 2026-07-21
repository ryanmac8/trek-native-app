import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../design/app_spacing.dart';
import '../../network/api_exception.dart';

/// Second step of login for accounts with TOTP MFA enabled — reached from
/// [LoginScreen] with the short-lived `mfaToken` returned by
/// `AuthService.login`. On success, [AuthService.isAuthenticated] flips to
/// `true` and the router redirects to `/trips` on its own.
class MfaScreen extends ConsumerStatefulWidget {
  const MfaScreen({super.key, required this.mfaToken});

  final String mfaToken;

  @override
  ConsumerState<MfaScreen> createState() => _MfaScreenState();
}

class _MfaScreenState extends ConsumerState<MfaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ref
          .read(authServiceProvider)
          .verifyMfaLogin(
            mfaToken: widget.mfaToken,
            code: _codeController.text.trim(),
          );
      // The router redirects to /trips automatically once isAuthenticated
      // flips to true. Mark unlocked too — the MFA code already proved
      // identity, an immediate biometric prompt right after would be
      // redundant.
      ref.read(appLockStateProvider).isUnlocked.value = true;
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor authentication')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter the 6-digit code from your authenticator app.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _codeController,
                  decoration: const InputDecoration(labelText: 'Code'),
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  validator: (value) {
                    if (value == null || value.trim().length != 6) {
                      return 'Enter the 6-digit code.';
                    }
                    return null;
                  },
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
