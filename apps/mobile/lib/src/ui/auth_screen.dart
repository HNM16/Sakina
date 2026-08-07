import 'package:flutter/material.dart';

import '../api_client.dart';
import '../l10n.dart';
import '../session.dart';

/// Phone number, then a six-digit code. No password, no email — the phone is
/// the account, which is what every messenger in the region does and what the
/// payments layer will eventually need anyway.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.session, required this.onSignedIn});

  final ApiClient api;
  final Session session;
  final VoidCallback onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController(text: '+992');
  final _codeController = TextEditingController();

  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final devCode = await widget.api.requestOtp(_phoneController.text.trim());
      setState(() {
        _codeSent = true;
        // Present only while the API runs the stub SMS provider, so the app is
        // testable before an operator agreement exists.
        if (devCode != null) _codeController.text = devCode;
      });
    } on ApiException catch (err) {
      setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await widget.api.verifyOtp(
        phone: _phoneController.text.trim(),
        code: _codeController.text.trim(),
        deviceId: widget.session.deviceId,
        deviceName: 'Flutter client',
      );

      await widget.session.save(
        accessToken: result.tokens.accessToken,
        refreshToken: result.tokens.refreshToken,
        user: result.user,
      );

      widget.api.accessToken = result.tokens.accessToken;
      widget.onSignedIn();
    } on ApiException catch (err) {
      setState(() => _error = err.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.t('app_name'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _phoneController,
                    enabled: !_codeSent,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l10n.t('phone_title'),
                      hintText: l10n.t('phone_hint'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  if (_codeSent) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: l10n.t('code_title'),
                        hintText: l10n.t('code_hint'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : (_codeSent ? _verify : _requestCode),
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.t('continue')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
