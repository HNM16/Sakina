// The theme picker, owned by the Profile section.
//
// Built off `sakinaThemes` rather than a hardcoded pair, so a theme added to
// that list appears here with nothing changed in this file.
import 'package:flutter/material.dart';

import '../../../l10n.dart';
import '../../../layout.dart';
import '../../themes/themes.dart';

Future<void> showThemeSheet(
  BuildContext context, {
  required String? current,
  required Future<void> Function(String? id) onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final l10n = L10n.of(sheetContext);
      final layout = SakinaLayout.of(sheetContext);

      Future<void> choose(String? id) async {
        await onChanged(id);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      }

      return SafeArea(
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
                    l10n.t('theme'),
                    style: Theme.of(sheetContext).textTheme.titleMedium,
                  ),
                ),
              ),
              SizedBox(height: layout.gap),
              for (final theme in sakinaThemes)
                RadioListTile<String?>(
                  value: theme.id,
                  secondary: Icon(
                    theme.brightness == Brightness.dark
                        ? Icons.dark_mode_outlined
                        : Icons.light_mode_outlined,
                  ),
                  title: Text(l10n.t(theme.labelKey)),
                ),
              // Following the phone is a real choice and not the absence of
              // one, so it gets a row like any other — same reasoning as the
              // language picker next door.
              RadioListTile<String?>(
                value: null,
                secondary: const Icon(Icons.brightness_auto_outlined),
                title: Text(l10n.t('theme_system')),
              ),
              SizedBox(height: layout.gap),
            ],
          ),
        ),
      );
    },
  );
}

/// What the Profile row shows underneath "Theme".
String themeSubtitle(BuildContext context, String? id) {
  final l10n = L10n.of(context);
  final chosen = SakinaThemes.byId(id);
  return chosen == null ? l10n.t('theme_system') : l10n.t(chosen.labelKey);
}
