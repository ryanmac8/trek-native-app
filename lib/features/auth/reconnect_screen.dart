import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_messenger.dart';
import '../../app/providers.dart';
import '../../auth/auth_service.dart';
import '../../design/app_spacing.dart';
import '../../network/api_exception.dart';

/// Reached by tapping the sync-status banner's "Reconnect" action when
/// `AuthService.needsReconnect` is set — the user is already inside the
/// app (never signed out for this), so this just re-runs [AuthService.login]
/// in place rather than being a full logout/login round-trip.
///
/// Unlike [LoginScreen], the MFA step (if the account has it enabled) is
/// handled inline on this same screen instead of pushing `/login/mfa`:
/// that route is gated by "not authenticated," and the user here still is
/// authenticated (that's the whole point of not signing them out), so
/// pushing it would just bounce straight back via the router's redirect.
class ReconnectScreen extends ConsumerStatefulWidget {
  const ReconnectScreen({super.key});

  @override
  ConsumerState<ReconnectScreen> createState() => _ReconnectScreenState();
}

class _ReconnectScreenState extends ConsumerState<ReconnectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  String? _mfaToken;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
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
      final authService = ref.read(authServiceProvider);
      if (_mfaToken == null) {
        final result = await authService.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
        if (result is MfaRequired) {
          setState(() => _mfaToken = result.mfaToken);
          return;
        }
      } else {
        await authService.verifyMfaLogin(
          mfaToken: _mfaToken!,
          code: _codeController.text.trim(),
        );
      }

      if (mounted) {
        AppMessenger.showSuccess('Reconnected to Trek.');
        context.canPop() ? context.pop() : context.go('/trips');
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onMfaStep = _mfaToken != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Reconnect to Trek')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  onMfaStep
                      ? 'Enter the 6-digit code from your authenticator app.'
                      : 'Your Trek session needs to be re-established. Log '
                            'in again to keep syncing — you can keep using '
                            'the app in the meantime.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (onMfaStep)
                  TextFormField(
                    controller: _codeController,
                    decoration: const InputDecoration(labelText: 'Code'),
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    autofocus: true,
                    validator: (value) {
                      if (value == null || value.trim().length != 6) {
                        return 'Enter the 6-digit code.';
                      }
                      return null;
                    },
                  )
                else ...[
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'Email'),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (value) =>
                        (value == null || value.trim().isEmpty)
                        ? 'Enter your email.'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _passwordController,
                    decoration: const InputDecoration(labelText: 'Password'),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Enter your password.'
                        : null,
                  ),
                ],
                if (_errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(onMfaStep ? 'Verify' : 'Reconnect'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
