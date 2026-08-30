import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n.dart';
import '../../../layout.dart';
import '../../../motion.dart';
import '../../../theme.dart';
import 'language_sheet.dart';
import 'theme_sheet.dart';

/// Who you are, and the handful of settings that are genuinely yours.
///
/// The language picker and sign-out used to be two icons in the chat list's app
/// bar, which is where settings go in an app that has nowhere else to put them.
/// They live here now.
///
/// ## Where the work goes
///
/// Everything below is additive — a row, or a section of rows:
///
///  - **Editing the name and the avatar.** Needs a `PATCH /v1/users/me` that
///    does not exist yet, and avatar upload can reuse `MediaService`.
///  - **A username**, so people can be found by handle rather than by id.
///  - **Notification settings**, once there is more than one thing to notify.
///  - **Privacy, sessions, blocked users** — each its own pushed screen on this
///    section's navigator.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.selfId,
    required this.selfName,
    required this.language,
    required this.onLanguageChanged,
    required this.themeId,
    required this.onThemeChanged,
    required this.onSignOut,
  });

  final String selfId;

  /// What the server called this account at sign-in. Null on an account that
  /// has never been given a name, which is most of them right now.
  final String? selfName;

  final String? language;
  final Future<void> Function(String? code) onLanguageChanged;

  /// The chosen theme's id, or null to follow the phone.
  final String? themeId;
  final Future<void> Function(String? id) onThemeChanged;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final layout = SakinaLayout.of(context);
    final palette = SakinaPalette.of(context);
    final text = Theme.of(context).textTheme;

    final name = selfName?.trim().isNotEmpty ?? false
        ? selfName!.trim()
        : l10n.t('profile_unnamed');
    final initial = name.characters.isEmpty ? '?' : name.characters.first.toUpperCase();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('profile'))),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: layout.gap),
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: layout.gutter,
              vertical: layout.gap,
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(initial, style: text.headlineSmall),
                ),
                SizedBox(width: layout.gutter),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: text.titleLarge, maxLines: 2),
                      SizedBox(height: layout.gap * 0.3),
                      // The id is the only handle that exists today, so it is
                      // shown rather than hidden — someone has to be able to
                      // read it out to be added to a chat.
                      Text(
                        selfId,
                        style: text.bodySmall?.copyWith(color: palette.muted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_outlined),
                  tooltip: l10n.t('profile_copy_id'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: selfId));
                    SakinaHaptics.threshold(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.t('profile_id_copied'))),
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(l10n.t('language')),
            subtitle: Text(
              language == null
                  ? l10n.t('language_system')
                  : L10n.languageNames[language] ?? language!,
            ),
            onTap: () => showLanguageSheet(
              context,
              current: language,
              onChanged: onLanguageChanged,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n.t('theme')),
            subtitle: Text(themeSubtitle(context, themeId)),
            onTap: () => showThemeSheet(
              context,
              current: themeId,
              onChanged: onThemeChanged,
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: palette.anor),
            title: Text(
              l10n.t('sign_out'),
              style: TextStyle(color: palette.anor),
            ),
            onTap: onSignOut,
          ),
        ],
      ),
    );
  }
}
