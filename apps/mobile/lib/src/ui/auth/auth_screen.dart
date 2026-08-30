import 'package:flutter/material.dart';

import '../../api_client.dart';
import '../../l10n.dart';
import '../../layout.dart';
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
  const AuthScreen({
    super.key,
    required this.api,
    required this.session,
    required this.onSignedIn,
    required this.onLanguageChanged,
  });

  final ApiClient api;
  final Session session;
  final VoidCallback onSignedIn;

  /// Applied immediately, so the rest of sign-up is already in the language
  /// the user just picked. Persisted by the app, and changeable afterwards in
  /// Profile.
  final Future<void> Function(String? code) onLanguageChanged;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

enum _Step { language, address, code }

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _inviteController = TextEditingController();

  /// Asked once, before anything else.
  ///
  /// Everything after this screen is text the user has to read, so the language
  /// is the first thing worth knowing. Someone who has already chosen — on this
  /// install or a previous sign-in, since the choice survives sign-out — skips
  /// straight past it.
  late _Step _step =
      widget.session.language == null ? _Step.language : _Step.address;
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

  Future<void> _chooseLanguage(String code) async {
    await widget.onLanguageChanged(code);
    if (!mounted) return;
    setState(() => _step = _Step.address);
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
                  children: switch (_step) {
                    _Step.language => _languageStep(),
                    _Step.address => _addressStep(l10n),
                    _Step.code => _codeStep(l10n),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pick a language, before the app has asked you to read anything.
  ///
  /// Three decisions here are the screen rather than decoration on it.
  ///
  /// **The heading is in all three languages at once.** Everywhere else in the
  /// app a heading can assume a language; this is the one screen where it
  /// cannot, because the person reading it has by definition not said yet.
  ///
  /// **No flags.** A flag is a country and this is a language: Russian is not
  /// only Russia, and Tajik is written in Cyrillic here and in Perso-Arabic
  /// across the border. A flag would be wrong information rather than
  /// decoration that happens to be redundant.
  ///
  /// **One tap commits and moves on.** A confirm button would be a second step
  /// asking someone to confirm that they can read — and the tap on your own
  /// language is not an ambiguous gesture.
  List<Widget> _languageStep() {
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);
    final text = Theme.of(context).textTheme;
    final active = widget.session.language ??
        Localizations.localeOf(context).languageCode;

    return [
      const Center(child: ChorkhonaMark(size: 56)),
      SizedBox(height: layout.gap * 1.5),
      Text(
        // "Язык · Забон · Language", assembled from the same key resolved in
        // each locale — so it stays correct if the wording is ever revised.
        L10n.supportedLocales
            .map((locale) => L10n(locale).t('language'))
            .join('  ·  '),
        textAlign: TextAlign.center,
        style: text.bodyMedium?.copyWith(color: palette.muted),
      ),
      SizedBox(height: layout.gap * 1.5),
      for (final locale in L10n.supportedLocales)
        Padding(
          padding: EdgeInsets.only(bottom: layout.gap * 0.6),
          child: _LanguageChoice(
            code: locale.languageCode,
            // Endonymic: every language named in itself. "Russian" written in
            // English is no help to somebody who only reads Tajik, which is
            // the entire point of this screen.
            name: L10n.languageNames[locale.languageCode] ?? locale.languageCode,
            selected: locale.languageCode == active,
            onTap: () => _chooseLanguage(locale.languageCode),
          ),
        ),
    ];
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


/// One language, as a row you tap.
///
/// Deliberately a plain bordered row rather than a card: this screen is a list
/// of three equal choices, and a card would imply a hierarchy among them that
/// does not exist.
class _LanguageChoice extends StatelessWidget {
  const _LanguageChoice({
    required this.code,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String code;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        // 12 is what the rest of the app already uses more than any other
        // radius; matching it is the point, not a preference.
        borderRadius: BorderRadius.circular(12),
        child: Semantics(
          selected: selected,
          button: true,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: layout.gutter,
              vertical: layout.gap,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : palette.line,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (selected) Icon(Icons.check, size: 20, color: scheme.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
