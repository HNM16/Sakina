import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../l10n.dart';
import '../../session.dart';
import '../../theme.dart';

/// Two steps: address, then the six-digit code.
///
/// Email rather than phone for now, because the team cannot receive +992 SMS
/// from outside Tajikistan. The server treats it as one identity kind among
/// several, so adding "continue with phone number" later is a second button,
/// not a second flow.
///
/// Three of Nielsen's heuristics do real work on this screen and are worth
/// naming, because sign-in is where a messenger loses people before it has ever
/// shown them anything:
///
///  - **User control and freedom** (#3). The address stays editable after the
///    code is sent, via an explicit back step. A typo'd address with no way back
///    is a dead end, and a dead end on the first screen is an uninstall.
///  - **Recognition rather than recall** (#6). The code step shows which address
///    the code went to, so nobody has to remember what they typed thirty
///    seconds ago in a different app.
///  - **Error prevention** (#5). The address is checked for shape before the
///    request goes out, so the common mistake is caught without a round trip.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.session, required this.onSignedIn});

  final ApiClient api;
  final Session session;
  final VoidCallback onSignedIn;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Step { address, code }

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _inviteController = TextEditingController();

  _Step _step = _Step.address;
  bool _busy = false;
  String? _error;
  bool _needsInvite = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _inviteController.dispose();
    super.dispose();
  }

  bool get _emailLooksValid {
    final value = _emailController.text.trim();
    final at = value.lastIndexOf('@');
    return at > 0 && at < value.length - 1 && value.substring(at).contains('.');
  }

  Future<void> _requestCode() async {
    if (!_emailLooksValid) {
      setState(() => _error = L10n.of(context).t('email_invalid'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final locale = Localizations.localeOf(context).languageCode;
      final devCode = await widget.api.requestOtp(_emailController.text.trim(), locale: locale);

      setState(() {
        _step = _Step.code;
        // Present only while the server runs a stub provider, so the app is
        // testable before any email vendor is wired up.
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
        email: _emailController.text.trim(),
        code: _codeController.text.trim(),
        deviceId: widget.session.deviceId,
        deviceName: 'Flutter client',
        inviteCode: _inviteController.text.trim(),
      );

      await widget.session.save(
        accessToken: result.tokens.accessToken,
        refreshToken: result.tokens.refreshToken,
        user: result.user,
      );

      widget.api.accessToken = result.tokens.accessToken;
      widget.onSignedIn();
    } on ApiException catch (err) {
      setState(() {
        _error = err.message;
        // The server only reveals invite-only status at verify time, so the
        // field appears exactly when it becomes relevant.
        if (err.code == 'forbidden' && err.message.toLowerCase().contains('invite')) {
          _needsInvite = true;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _backToAddress() {
    setState(() {
      _step = _Step.address;
      _codeController.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final onCodeStep = _step == _Step.code;

    return Scaffold(
      appBar: onCodeStep
          ? AppBar(
              // The escape hatch. Without it a mistyped address is unrecoverable.
              leading: BackButton(onPressed: _busy ? null : _backToAddress),
              title: Text(l10n.t('code_title')),
            )
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: onCodeStep ? _codeStep(l10n) : _addressStep(l10n),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _addressStep(L10n l10n) => [
        const Center(child: ChorkhonaMark(size: 64)),
        const SizedBox(height: 20),
        Text(
          l10n.t('app_name'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.t('sign_in_subtitle'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _requestCode(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          decoration: InputDecoration(
            labelText: l10n.t('email_title'),
            hintText: l10n.t('email_hint'),
            border: const OutlineInputBorder(),
            errorText: _error,
          ),
        ),
        const SizedBox(height: 24),
        _submitButton(l10n.t('continue'), _requestCode),
      ];

  List<Widget> _codeStep(L10n l10n) => [
        // Recognition, not recall: the address is on screen, not in memory.
        Text(
          l10n.t('code_sent_to'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          _emailController.text.trim(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          autofocus: true,
          maxLength: 6,
          autofillHints: const [AutofillHints.oneTimeCode],
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _verify(),
          decoration: InputDecoration(
            labelText: l10n.t('code_title'),
            hintText: l10n.t('code_hint'),
            border: const OutlineInputBorder(),
            counterText: '',
            errorText: _error,
          ),
        ),
        if (_needsInvite) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _inviteController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.t('invite_title'),
              hintText: l10n.t('invite_hint'),
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 24),
        _submitButton(l10n.t('continue'), _verify),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _backToAddress,
          child: Text(l10n.t('change_email')),
        ),
      ];

  Widget _submitButton(String label, VoidCallback onPressed) => FilledButton(
        onPressed: _busy ? null : onPressed,
        child: _busy
            // Visibility of system status: on a slow connection this button is
            // the only thing telling the user anything is happening.
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      );
}
