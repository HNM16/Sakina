// The language picker, owned by the Profile section.
//
// Endonymic by rule: every language is named in itself. See docs/BRAND.md and
// the note in l10n.dart — "Russian" written in English is no help to someone
// who only reads Tajik.
import 'package:flutter/material.dart';

import '../../../l10n.dart';
import '../../../layout.dart';

/// The language picker.
///
/// Endonymic: every language is named in itself. "Russian" written in English
/// is no help to someone who only reads Tajik, which is why every real language
/// switcher on earth works this way.
Future<void> showLanguageSheet(
  BuildContext context, {
  required String? current,
  required Future<void> Function(String? code) onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final l10n = L10n.of(sheetContext);
      final layout = SakinaLayout.of(sheetContext);

      Future<void> choose(String? value) async {
        await onChanged(value);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      }

      return SafeArea(
        // The selection lives on the group rather than on each tile: a Radio
        // that carries its own groupValue is deprecated, and one source of
        // truth for "which is chosen" was always the right shape anyway.
        child: RadioGroup<String?>(
          groupValue: current,
          onChanged: choose,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: layout.gutter),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.t('language'),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              SizedBox(height: layout.gap),
              for (final code in L10n.supportedLocales.map((l) => l.languageCode))
                RadioListTile<String?>(
                  value: code,
                  title: Text(L10n.languageNames[code] ?? code),
                ),
              // Null is "follow the phone", which is a real choice and not the
              // absence of one — so it gets a row like any other.
              RadioListTile<String?>(
                value: null,
                title: Text(l10n.t('language_system')),
              ),
              SizedBox(height: layout.gap),
            ],
          ),
        ),
      );
    },
  );
}

/// Choosing what kind of attachment to send.
///
/// Camera before gallery for photos and video, because the common case in a
/// family chat is something happening right now.
