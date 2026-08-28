import 'package:flutter/material.dart';

import '../../chat_repository.dart';
import '../../media_service.dart';

/// Everything a section is allowed to know about the app around it.
///
/// Handed *in* rather than reached for. A section never imports `main.dart`,
/// never imports another section, and never digs a dependency out of an
/// InheritedWidget it did not declare — so a section can be rewritten, or
/// deleted, without any other section noticing.
///
/// ## Adding a capability
///
/// When a section needs something new — a payments client, a mini-app host,
/// a call controller — add a field here and populate it in `main.dart`.
/// Existing sections are unaffected: they simply do not read it. That is the
/// whole reason this is one object rather than a per-section parameter list.
///
/// Nullable fields are the exception worth allowing: a capability that does
/// not exist yet (calls has no signalling, explore has no feed) is honestly
/// null, and the section shows the state that says so rather than pretending.
@immutable
class SectionScope {
  const SectionScope({
    required this.repository,
    required this.media,
    required this.selfName,
    required this.language,
    required this.onLanguageChanged,
    required this.onSignOut,
  });

  /// Chats, messages and the socket. Owned by the app, shared by reference.
  final ChatRepository repository;

  /// Uploads and downloads for attachments.
  final MediaService media;

  /// What the server called this account at sign-in, or null for one that has
  /// never been named.
  final String? selfName;

  /// The language the user picked, or null to follow the phone.
  final String? language;
  final Future<void> Function(String? code) onLanguageChanged;

  /// Tears down the session. Lives on the app, not on a section, because it
  /// disposes things every section is holding.
  final VoidCallback onSignOut;
}

/// One tab of the app.
///
/// A section is a *declaration*, not a widget: it says what it is called, what
/// it looks like in the bar, and how to build its root. The shell renders it
/// without knowing anything else, which is what lets the shell stay fixed while
/// the sections behind it change shape over and over.
///
/// Everything a section owns lives under `ui/sections/<id>/`. Shared vocabulary
/// — motion primitives, skeletons, indicators, the mark — lives in `ui/` and
/// may be used by any of them. `pnpm test:sections` fails the build if one
/// section imports another.
@immutable
abstract class SakinaSection {
  const SakinaSection();

  /// Stable identifier. Used for the navigator key, the page storage bucket and
  /// the widget key, so it must not change once shipped — a rename would
  /// silently discard the scroll position and stack it was holding.
  String get id;

  /// Key into [L10n]. The label is translated at build time, not stored here,
  /// because the bar rebuilds when the language changes.
  String get labelKey;

  IconData get icon;

  /// Shown when the tab is selected. Material's convention is a filled
  /// counterpart to the outlined resting icon; it carries the selection for
  /// anyone who cannot see the accent colour.
  IconData get selectedIcon;

  /// The section's root screen. Pushes from here stay inside this section's own
  /// navigator, so switching tabs does not lose your place.
  Widget build(BuildContext context, SectionScope scope);
}
